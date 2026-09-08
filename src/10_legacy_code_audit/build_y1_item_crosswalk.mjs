#!/usr/bin/env node
/** Build a protected Year 1 source-variable-to-analytic-item crosswalk. */

import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const requiredEnv = ["MOROCCO_Y1_ROOT", "MOROCCO_WORK_ROOT"];
for (const name of requiredEnv) {
  if (!process.env[name]) throw new Error(`Missing required environment variable: ${name}`);
}

const y1Root = path.resolve(process.env.MOROCCO_Y1_ROOT);
const workRoot = path.resolve(process.env.MOROCCO_WORK_ROOT);
const outputDir = path.join(workRoot, "outputs/y1_y3_irt/00_y1_reference/item_crosswalk");
const parameterDir = path.join(workRoot, "outputs/y1_y3_irt/00_y1_reference/ster_probe");

function isWithin(candidate, root) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

if (isWithin(outputDir, y1Root) || !isWithin(outputDir, workRoot) || outputDir === workRoot) {
  throw new Error(`Unsafe output directory: ${outputDir}`);
}

const inputs = {
  baseline: {
    codebook: path.join(y1Root, "3 - Data collection/Item map/stata_codebooks/baseline/baseline_tested_iecodebook.xlsx"),
    cleaningDo: path.join(y1Root, "5 - Data analysis/4_Baseline/Setup/4_baseline-cleaning-20240729-neam.do"),
  },
  endline: {
    codebook: path.join(y1Root, "3 - Data collection/Item map/stata_codebooks/endline/endline_tested_iecodebook.xlsx"),
    cleaningDo: path.join(y1Root, "5 - Data analysis/10_Endline/Setup/02_Endline_cleaning_2024-08-01_neam.do"),
  },
};
const finalScoringDo = path.join(
  y1Root,
  "5 - Data analysis/10_Endline/Analysis/Programs/01-Testscores-20251008-adb.do",
);

for (const spec of Object.values(inputs)) {
  for (const source of Object.values(spec)) {
    if (!isWithin(source, y1Root)) throw new Error(`Unsafe source path: ${source}`);
    await fs.access(source);
  }
}
if (!isWithin(finalScoringDo, y1Root)) throw new Error(`Unsafe source path: ${finalScoringDo}`);
await fs.access(finalScoringDo);

function subjectFromItem(itemId) {
  return { a: "arabic", f: "french", m: "maths" }[itemId[0]] ?? "";
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (char === '"') quoted = false;
      else field += char;
    } else if (char === '"') quoted = true;
    else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else field += char;
  }
  if (field || row.length) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }
  return rows;
}

function csvEscape(value) {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

const modelItems = new Map();
for (const subject of ["arabic", "french", "maths"]) {
  const file = path.join(parameterDir, `y1_${subject}_item_parameters.csv`);
  const parsed = parseCsv(await fs.readFile(file, "utf8"));
  const header = parsed[0];
  const itemIndex = header.indexOf("item_id");
  const fixedIndex = header.indexOf("fixed_in_combined_model");
  for (const row of parsed.slice(1)) {
    if (!row[itemIndex]) continue;
    modelItems.set(row[itemIndex], {
      subject,
      fixed: row[fixedIndex] === "1",
    });
  }
}

const records = [];
for (const [wave, spec] of Object.entries(inputs)) {
  const blob = await FileBlob.load(spec.codebook);
  const workbook = await SpreadsheetFile.importXlsx(blob);
  const values = workbook.worksheets.getItem("survey").getUsedRange(true).values;
  const header = values[0];
  const cleanIndex = header.indexOf("name");
  const sourceIndex = header.indexOf("name:current");
  if (cleanIndex < 0 || sourceIndex < 0) throw new Error(`Required columns absent in ${spec.codebook}`);

  for (let rowNumber = 2; rowNumber <= values.length; rowNumber += 1) {
    const row = values[rowNumber - 1];
    const analyticItemId = String(row[cleanIndex] ?? "").trim();
    const sourceVariable = String(row[sourceIndex] ?? "").trim();
    if (!/^[afm]\d+$/.test(analyticItemId) || !sourceVariable) continue;
    records.push({
      year: 1,
      wave,
      subject: subjectFromItem(analyticItemId),
      administeredGrade: "",
      formId: "",
      sourceVariable,
      intermediateVariable: analyticItemId,
      underlyingItemId: analyticItemId,
      analyticItemId,
      mappingStage: "iecodebook_direct",
      mappingEvidence: `y1_root/${path.relative(y1Root, spec.codebook)}#survey-row-${rowNumber}`,
      withinWaveAnchorIntent: "",
      crossWaveLinkIntent: "",
      storedModelRole: "",
      versionStatus: "requires_instrument_verification",
      administrationStatus: "requires_empirical_nonmissing_check",
    });
  }

  const doText = await fs.readFile(spec.cleaningDo, "utf8");
  const lines = doText.split(/\r?\n/);
  const compositeRegex = /^\s*egen\s+([afm]\d+)\s*=\s*rowmax\(([^)]+)\)/i;
  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const match = compositeRegex.exec(lines[lineIndex]);
    if (!match) continue;
    const analyticItemId = match[1].toLowerCase();
    const components = match[2].trim().split(/\s+/).filter(Boolean);
    for (const sourceVariable of components) {
      records.push({
        year: 1,
        wave,
        subject: subjectFromItem(analyticItemId),
        administeredGrade: "",
        formId: "",
        sourceVariable,
        intermediateVariable: sourceVariable,
        underlyingItemId: analyticItemId,
        analyticItemId,
        mappingStage: "constructed_common_item",
        mappingEvidence: `y1_root/${path.relative(y1Root, spec.cleaningDo)}#line-${lineIndex + 1}`,
        withinWaveAnchorIntent: "yes",
        crossWaveLinkIntent: "",
        storedModelRole: "",
        versionStatus: "requires_instrument_verification",
        administrationStatus: "requires_empirical_nonmissing_check",
      });
    }
  }
}

const wavesByItem = new Map();
for (const record of records) {
  if (!wavesByItem.has(record.analyticItemId)) wavesByItem.set(record.analyticItemId, new Set());
  wavesByItem.get(record.analyticItemId).add(record.wave);
}

for (const record of records) {
  const model = modelItems.get(record.analyticItemId);
  record.crossWaveLinkIntent = wavesByItem.get(record.analyticItemId).size > 1 ? "yes" : "";
  record.storedModelRole = !model
    ? "not_in_stored_model"
    : model.fixed
      ? "fixed_in_combined_model"
      : "estimated_in_combined_model";
}

let mappedModelItems = new Set(records.filter((record) => modelItems.has(record.analyticItemId)).map((record) => record.analyticItemId));
for (const [analyticItemId, model] of modelItems.entries()) {
  if (mappedModelItems.has(analyticItemId)) continue;
  let underlyingItemId = "";
  let wave = "";
  let administeredGrade = "";
  let mappingStage = "";
  let crossWaveLinkIntent = "";

  const baselineDriftMatch = /^bldf_([afm]\d+)$/.exec(analyticItemId);
  const gradeFreeMatch = /^([afm]\d+)_(1|2|3|4|5|6|23|456)$/.exec(analyticItemId);
  if (baselineDriftMatch) {
    underlyingItemId = baselineDriftMatch[1];
    wave = "baseline";
    mappingStage = "baseline_drift_copy";
    crossWaveLinkIntent = "no_drift_parameter_freed";
  } else if (gradeFreeMatch) {
    underlyingItemId = gradeFreeMatch[1];
    wave = "endline";
    administeredGrade = gradeFreeMatch[2].split("").join("|");
    mappingStage = "endline_grade_specific_free";
  }

  if (!underlyingItemId || !wavesByItem.has(underlyingItemId)) continue;
  records.push({
    year: 1,
    wave,
    subject: model.subject,
    administeredGrade,
    formId: "",
    sourceVariable: underlyingItemId,
    intermediateVariable: underlyingItemId,
    underlyingItemId,
    analyticItemId,
    mappingStage,
    mappingEvidence: `y1_root/${path.relative(y1Root, finalScoringDo)}`,
    withinWaveAnchorIntent: gradeFreeMatch ? "freed_across_grade_groups" : "",
    crossWaveLinkIntent,
    storedModelRole: model.fixed ? "fixed_in_combined_model" : "estimated_in_combined_model",
    versionStatus: "analytic_split_verified_item_version_requires_instrument_review",
    administrationStatus: administeredGrade ? "grade_group_from_scoring_code" : "requires_empirical_nonmissing_check",
  });
  mappedModelItems.add(analyticItemId);
}

for (const [analyticItemId, model] of modelItems.entries()) {
  if (mappedModelItems.has(analyticItemId)) continue;
  records.push({
    year: 1,
    wave: "",
    subject: model.subject,
    administeredGrade: "",
    formId: "",
    sourceVariable: "",
    intermediateVariable: analyticItemId,
    underlyingItemId: "",
    analyticItemId,
    mappingStage: "stored_model_unmapped",
    mappingEvidence: "work_root/outputs/y1_y3_irt/00_y1_reference/ster_probe",
    withinWaveAnchorIntent: "",
    crossWaveLinkIntent: "",
    storedModelRole: model.fixed ? "fixed_in_combined_model" : "estimated_in_combined_model",
    versionStatus: "requires_mapping_and_instrument_verification",
    administrationStatus: "requires_empirical_nonmissing_check",
  });
}

records.sort((left, right) =>
  String(left.subject).localeCompare(String(right.subject))
  || String(left.analyticItemId).localeCompare(String(right.analyticItemId), undefined, { numeric: true })
  || String(left.wave).localeCompare(String(right.wave))
  || String(left.sourceVariable).localeCompare(String(right.sourceVariable))
);

await fs.mkdir(outputDir, { recursive: true });
const fieldMap = [
  ["year", "year"],
  ["wave", "wave"],
  ["subject", "subject"],
  ["administered_grade", "administeredGrade"],
  ["form_id", "formId"],
  ["source_variable", "sourceVariable"],
  ["intermediate_variable", "intermediateVariable"],
  ["underlying_item_id", "underlyingItemId"],
  ["analytic_item_id", "analyticItemId"],
  ["mapping_stage", "mappingStage"],
  ["mapping_evidence", "mappingEvidence"],
  ["within_wave_anchor_intent", "withinWaveAnchorIntent"],
  ["cross_wave_link_intent", "crossWaveLinkIntent"],
  ["stored_model_role", "storedModelRole"],
  ["version_status", "versionStatus"],
  ["administration_status", "administrationStatus"],
];
const csvLines = [
  fieldMap.map(([header]) => csvEscape(header)).join(","),
  ...records.map((record) => fieldMap.map(([, key]) => csvEscape(record[key])).join(",")),
];
await fs.writeFile(path.join(outputDir, "y1_source_variable_item_crosswalk.csv"), `${csvLines.join("\n")}\n`, "utf8");

const modelItemsUnmapped = [...modelItems.keys()].filter((itemId) => !mappedModelItems.has(itemId));
const summary = {
  created_utc: new Date().toISOString(),
  rows: records.length,
  unique_analytic_item_ids: new Set(records.map((record) => record.analyticItemId)).size,
  model_items: modelItems.size,
  model_items_with_mapping: mappedModelItems.size,
  model_items_without_mapping: modelItemsUnmapped.length,
  direct_codebook_rows: records.filter((record) => record.mappingStage === "iecodebook_direct").length,
  constructed_common_item_rows: records.filter((record) => record.mappingStage === "constructed_common_item").length,
  intended_cross_wave_item_ids: [...wavesByItem.values()].filter((waves) => waves.size > 1).length,
  output: "y1_source_variable_item_crosswalk.csv",
};
await fs.writeFile(path.join(outputDir, "y1_item_crosswalk_summary.json"), `${JSON.stringify(summary, null, 2)}\n`, "utf8");
console.log(JSON.stringify(summary));
