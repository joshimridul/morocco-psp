import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const [workRoot, outputPath, previewDir] = process.argv.slice(2);
if (!workRoot || !outputPath || !previewDir) {
  throw new Error("Usage: node build_workbook.mjs <workRoot> <output.xlsx> <previewDir>");
}

const COLORS = {
  navy: "#17365D",
  blue: "#2E75B6",
  paleBlue: "#D9EAF7",
  paleGreen: "#E2F0D9",
  paleGold: "#FFF2CC",
  paleRed: "#FCE4D6",
  gray: "#F2F4F7",
  midGray: "#D9E1F2",
  text: "#1F2937",
  white: "#FFFFFF",
  border: "#D0D7DE",
};

function parseCsv(text) {
  text = text.replace(/^\uFEFF/, "");
  const rows = [];
  let row = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { row.push(field); field = ""; }
    else if (ch === '\n') { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += ch;
  }
  if (field.length || row.length) { row.push(field.replace(/\r$/, "")); rows.push(row); }
  return rows.filter(r => r.some(v => v !== ""));
}

function shouldBeNumeric(header) {
  const h = header.toLowerCase();
  if (/(^|_)item_id$|scto|source_id|link_id|fingerprint|sha256/.test(h)) return false;
  return /(^n$|_n$|^grade$|_grade$|count|rows?$|bytes|pct|percent|mean|sd$|se$|lower|upper|alpha|rmsea|srmsr|cfi|tli|aic|bic|eigen|ratio|share|difference|correlation|slope|intercept|rmse|difficulty|discrimination|point_biserial|warning_count|rank|question_number|replicates|likelihood|items_added|tail_only_items|candidate_total|minimum_each_tail|good_easy|good_hard)/.test(h);
}

function convertValue(value, header) {
  if (value === "") return null;
  if (shouldBeNumeric(header) && /^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/.test(value)) return Number(value);
  return value;
}

async function loadCsv(relative) {
  const text = await fs.readFile(path.join(workRoot, relative), "utf8");
  const rows = parseCsv(text);
  const headers = rows[0];
  return { headers, rows: rows.slice(1).map(row => headers.map((h, i) => convertValue(row[i] ?? "", h))) };
}

function colLetter(index) {
  let n = index + 1, s = "";
  while (n > 0) { n--; s = String.fromCharCode(65 + (n % 26)) + s; n = Math.floor(n / 26); }
  return s;
}

function widthFor(header) {
  const h = header.toLowerCase();
  if (/question_summary|item_text|suggested_surface_change|change_made|rationale|implementation|issue|consequence|provisional_action|notes|interpretation|primary_candidate|backup_candidate|instruction/.test(h)) return 44;
  if (/recommendation|status|source|role|link_ids|relative_path|full_version|confidence|domain_source|history|retain_current|add_from/.test(h)) return 28;
  if (/fingerprint|sha256/.test(h)) return 22;
  if (/item_id|scto|source_id|link_id/.test(h)) return 20;
  if (/subject|domain|model_type|wave|grade/.test(h)) return 14;
  if (shouldBeNumeric(header)) return 12;
  return Math.min(24, Math.max(12, header.length + 2));
}

function numberFormatFor(header) {
  const h = header.toLowerCase();
  if (/pct|percent/.test(h)) return "0.00";
  if (/p$|_p_|p_holm|p_cluster/.test(h)) return "0.000";
  if (/alpha|rmsea|srmsr|cfi|tli|ratio|share|correlation|slope|intercept|rmse|difference|difficulty|discrimination|point_biserial|estimate|mean|sd|se|lower|upper/.test(h)) return "0.000";
  if (/^n$|_n$|count|rows?$|bytes|grade$|question_number|warning_count|rank/.test(h)) return "#,##0";
  return null;
}

function addConditionalFormatting(sheet, headers, startRow, endRow) {
  const rules = [
    ["provisional_recommendation", "replace", COLORS.paleRed],
    ["provisional_recommendation", "revise", COLORS.paleGold],
    ["provisional_recommendation", "anchor", COLORS.paleGreen],
    ["anchor_candidate_tier", "Tier A", COLORS.paleGreen],
    ["anchor_candidate_tier", "not eligible", COLORS.paleRed],
    ["preliminary_coverage_status", "no common", COLORS.paleRed],
    ["preliminary_coverage_status", "no empirically", COLORS.paleRed],
    ["preliminary_coverage_status", "fewer than", COLORS.paleGold],
    ["priority", "change now", COLORS.paleRed],
    ["priority", "critical", COLORS.paleRed],
    ["priority", "conditional backup", COLORS.paleGold],
    ["priority", "targeted repair", COLORS.paleGold],
    ["status", "repair", COLORS.paleGold],
    ["status", "adequate", COLORS.paleGreen],
    ["review_status", "ready for content approval", COLORS.paleGreen],
    ["review_status", "required", COLORS.paleRed],
    ["review_status", "missing", COLORS.paleRed],
  ];
  for (const [header, text, fill] of rules) {
    const idx = headers.indexOf(header);
    if (idx >= 0) {
      const range = sheet.getRange(`${colLetter(idx)}${startRow}:${colLetter(idx)}${endRow}`);
      range.conditionalFormats.add("containsText", { text, format: { fill } });
    }
  }
}

function writeDataSheet(workbook, name, title, note, data, options = {}) {
  const sheet = workbook.worksheets.add(name);
  sheet.showGridLines = false;
  let headers = [...data.headers];
  let rows = data.rows.map(row => [...row]);
  if (options.appendDecisionColumns) {
    headers.push("ministry_final_decision", "ministry_comment");
    rows = rows.map(row => [...row, null, null]);
  }
  const lastCol = colLetter(headers.length - 1);
  sheet.mergeCells(`A1:${lastCol}1`);
  sheet.getRange("A1").values = [[title]];
  sheet.getRange(`A1:${lastCol}1`).format = {
    fill: COLORS.navy, font: { bold: true, color: COLORS.white, size: 16 },
    rowHeight: 28, verticalAlignment: "center",
  };
  sheet.mergeCells(`A2:${lastCol}2`);
  sheet.getRange("A2").values = [[note]];
  sheet.getRange(`A2:${lastCol}2`).format = {
    fill: COLORS.gray, font: { color: COLORS.text, italic: true, size: 9 },
    wrapText: true, rowHeight: 34, verticalAlignment: "center",
  };
  const headerRow = 4;
  const endRow = headerRow + rows.length;
  sheet.getRange(`A${headerRow}:${lastCol}${endRow}`).values = [headers, ...rows];
  sheet.getRange(`A${headerRow}:${lastCol}${headerRow}`).format = {
    fill: COLORS.blue, font: { bold: true, color: COLORS.white, size: 9 },
    wrapText: true, rowHeight: 34, verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: COLORS.border },
  };
  if (rows.length) {
    sheet.getRange(`A${headerRow + 1}:${lastCol}${endRow}`).format = {
      font: { color: COLORS.text, size: 9 }, verticalAlignment: "top",
      borders: { insideHorizontal: { style: "thin", color: "#E5E7EB" } },
    };
    const table = sheet.tables.add(`A${headerRow}:${lastCol}${endRow}`, true, `${name.replace(/[^A-Za-z0-9]/g, "")}Table`);
    table.style = "TableStyleMedium2";
    table.showBandedRows = true;
    table.showFilterButton = true;
  }
  headers.forEach((header, i) => {
    const col = colLetter(i);
    sheet.getRange(`${col}1:${col}${Math.max(endRow, 4)}`).format.columnWidth = widthFor(header);
    const nf = numberFormatFor(header);
    if (nf && rows.length) sheet.getRange(`${col}${headerRow + 1}:${col}${endRow}`).format.numberFormat = nf;
    if (/summary|rationale|recommendation|issue|action|notes|status|source|path|link_ids|implementation|confidence|review|candidate|history|instruction|retain_current|add_from/.test(header.toLowerCase())) {
      sheet.getRange(`${col}${headerRow + 1}:${col}${endRow}`).format.wrapText = true;
    }
  });
  sheet.freezePanes.freezeRows(headerRow);
  sheet.freezePanes.freezeColumns(Math.min(options.freezeColumns ?? 3, headers.length));
  addConditionalFormatting(sheet, headers, headerRow + 1, endRow);
  if (options.appendDecisionColumns && rows.length) {
    const idx = headers.indexOf("ministry_final_decision");
    sheet.getRange(`${colLetter(idx)}${headerRow + 1}:${colLetter(idx)}${endRow}`).dataValidation = {
      rule: { type: "list", values: ["Approve as recommended", "Retain unchanged", "Revise", "Replace", "Defer"] }
    };
    sheet.getRange(`${colLetter(idx)}${headerRow + 1}:${colLetter(idx + 1)}${endRow}`).format.fill = "#FFFBEA";
  }
  const existingDecisionIdx = headers.indexOf("ministry_decision");
  if (existingDecisionIdx >= 0 && rows.length) {
    sheet.getRange(`${colLetter(existingDecisionIdx)}${headerRow + 1}:${colLetter(existingDecisionIdx)}${endRow}`).dataValidation = {
      rule: { type: "list", values: ["Approve proposal", "Use backup", "Keep current", "Revise proposal", "Discuss"] }
    };
    const commentIdx = headers.indexOf("ministry_comment");
    const finalIdx = commentIdx >= 0 ? commentIdx : existingDecisionIdx;
    sheet.getRange(`${colLetter(existingDecisionIdx)}${headerRow + 1}:${colLetter(finalIdx)}${endRow}`).format.fill = "#FFFBEA";
  }
  return { sheet, headers, headerRow, endRow };
}

const sourceRegistry = await loadCsv("outputs/y3_ministry/00_readiness/y3_source_registry.csv");
const blockingIssues = await loadCsv("outputs/y3_ministry/00_readiness/y3_blocking_issues.csv");
const formScores = await loadCsv("derived/y3_ministry/y3_form_score_summary.csv");
const formUncertainty = await loadCsv("outputs/y3_ministry/01_item_quality/y3_form_reliability_uncertainty.csv");
const dimensions = await loadCsv("outputs/y3_ministry/01_item_quality/y3_form_dimensionality.csv");
const modelSummary = await loadCsv("outputs/y3_ministry/01_item_quality/y3_irt_model_summary.csv");
const itemDecisions = await loadCsv("outputs/y3_ministry/03_forms/y3_ministry_item_decisions.csv");
const anchorCandidates = await loadCsv("derived/y3_ministry/y3_anchor_candidate_evidence.csv");
const anchorCoverage = await loadCsv("outputs/y3_ministry/02_anchors/y3_anchor_link_coverage.csv");
const anchorSensitivity = await loadCsv("outputs/y3_ministry/02_anchors/y3_anchor_set_sensitivity.csv");
const trendCandidates = await loadCsv("outputs/y3_ministry/02_anchors/y3_across_year_trend_candidates.csv");
const domains = await loadCsv("outputs/y3_ministry/03_forms/y3_completed_domain_map.csv");
const shiftMap = await loadCsv("outputs/y3_ministry/03_forms/y3_one_grade_shift_map.csv");
const frenchForms = await loadCsv("outputs/y3_ministry/03_forms/y3_french_grade_specific_redesign.csv");
const advice = await loadCsv("outputs/y3_ministry/03_forms/y3_instrument_advice.csv");
const actionShortlist = await loadCsv("outputs/y3_ministry/03_forms/y3_minimal_replacement_actions.csv");
const anchorRepairs = await loadCsv("outputs/y3_ministry/03_forms/y3_minimal_anchor_repairs.csv");
const tailCoverage = await loadCsv("outputs/y3_ministry/03_forms/y3_tail_coverage_check.csv");
const pilotItemBank = await loadCsv("outputs/y3_ministry/03_forms/y3_pilot_item_bank.csv");

function rowsToObjects(data) {
  return data.rows.map(row => Object.fromEntries(data.headers.map((h, i) => [h, row[i]])));
}
const scoreObjects = rowsToObjects(formScores);
const uncertaintyMap = new Map(rowsToObjects(formUncertainty).map(r => [`${r.wave}|${r.subject}|${r.grade}`, r]));
const dimensionMap = new Map(rowsToObjects(dimensions).map(r => [`${r.wave}|${r.subject}|${r.grade}`, r]));
const primaryModelMap = new Map(rowsToObjects(modelSummary).filter(r => r.primary_model === 1).map(r => [`${r.wave}|${r.subject}|${r.grade}`, r]));
const formPropertyHeaders = [
  "wave", "subject", "grade", "n_deduplicated", "binary_item_n", "continuous_or_rubric_item_n",
  "proportion_score_mean", "floor_pct", "ceiling_pct", "alpha", "alpha_bootstrap_lower", "alpha_bootstrap_upper",
  "eigen1_eigen2_ratio", "first_eigen_variance_share", "primary_model", "model_converged", "RMSEA", "SRMSR", "CFI",
];
const formPropertyRows = scoreObjects.map(r => {
  const key = `${r.wave}|${r.subject}|${r.grade}`;
  const u = uncertaintyMap.get(key) || {}, d = dimensionMap.get(key) || {}, m = primaryModelMap.get(key) || {};
  return [r.wave, r.subject, r.grade, r.n_deduplicated, r.binary_item_n, r.continuous_or_rubric_item_n,
    r.proportion_score_mean, r.floor_pct, r.ceiling_pct, u.alpha, u.alpha_school_bootstrap_lower,
    u.alpha_school_bootstrap_upper, d.eigen1_eigen2_ratio, d.first_eigen_variance_share,
    m.model_type, m.converged, m.RMSEA, m.SRMSR, m.CFI];
});
const formProperties = { headers: formPropertyHeaders, rows: formPropertyRows };

const workbook = Workbook.create();

// Executive summary.
const summary = workbook.worksheets.add("Executive Summary");
summary.showGridLines = false;
summary.mergeCells("A1:H1");
summary.getRange("A1").values = [["Morocco Pioneer Schools — Year 3 Item & Anchor Audit"]];
summary.getRange("A1:H1").format = { fill: COLORS.navy, font: { bold: true, color: COLORS.white, size: 18 }, rowHeight: 32 };
summary.mergeCells("A2:H2");
summary.getRange("A2").values = [["Treatment-blind evidence for item quality, linking, Ministry completion, grade shifting, and next-form design | 4 August 2026"]];
summary.getRange("A2:H2").format = { fill: COLORS.gray, font: { color: COLORS.text, italic: true, size: 10 }, rowHeight: 24 };
summary.getRange("A4:B4").merge(); summary.getRange("A4").values = [["Measurement evidence"]];
summary.getRange("D4:E4").merge(); summary.getRange("D4").values = [["Anchor coverage"]];
summary.getRange("G4:H4").merge(); summary.getRange("G4").values = [["Ministry completion"]];
for (const r of ["A4:B4", "D4:E4", "G4:H4"]) summary.getRange(r).format = { fill: COLORS.blue, font: { bold: true, color: COLORS.white } };
summary.getRange("A5:A10").values = [["Forms audited"], ["Reliability, minimum"], ["Reliability, maximum"], ["IRT models fit"], ["Models converged"], ["Endline binary item×grade rows"]];
summary.getRange("D5:D10").values = [["Required links"], ["Links with ≥5 candidates"], ["Links with <5 candidates"], ["Links with no eligible candidate"], ["Links with no common item"], ["Tier A link-item candidates"]];
summary.getRange("G5:G10").values = [["Endline item×grade rows"], ["Domain rows completed"], ["Non-Ministry domain rows"], ["One-grade shift rows"], ["French grade forms proposed"], ["Blocking issues"]];
const fpEnd = 4 + formProperties.rows.length;
const lcEnd = 4 + anchorCoverage.rows.length;
const acEnd = 4 + anchorCandidates.rows.length;
const idEnd = 4 + itemDecisions.rows.length;
const dmEnd = 4 + domains.rows.length;
const shEnd = 4 + shiftMap.rows.length;
const biEnd = 4 + blockingIssues.rows.length;
const msEnd = 4 + modelSummary.rows.length;
const asEnd = 4 + actionShortlist.rows.length;
const arEnd = 4 + anchorRepairs.rows.length;
const tcEnd = 4 + tailCoverage.rows.length;
function hidx(data, name) { return data.headers.indexOf(name); }
const alphaCol = colLetter(formPropertyHeaders.indexOf("alpha"));
const statusCol = colLetter(hidx(anchorCoverage, "preliminary_coverage_status"));
const tierCol = colLetter(hidx(anchorCandidates, "anchor_candidate_tier"));
const domainConfirmCol = colLetter(hidx(domains, "requires_ministry_confirmation"));
const itemTypeCol = colLetter(hidx(itemDecisions, "item_type"));
const modelConvergedCol = colLetter(hidx(modelSummary, "converged"));
const actionPriorityCol = colLetter(hidx(actionShortlist, "priority"));
const anchorItemsAddedCol = colLetter(hidx(anchorRepairs, "items_added"));
const anchorCandidateTotalCol = colLetter(hidx(anchorRepairs, "candidate_total_after_proposal"));
const tailStatusCol = colLetter(hidx(tailCoverage, "status"));
const tailOnlyCol = colLetter(hidx(tailCoverage, "net_new_tail_only_items"));
summary.getRange("B5:B10").formulas = [
  [`=COUNTA('Form Properties'!A5:A${fpEnd})`],
  [`=MIN('Form Properties'!${alphaCol}5:${alphaCol}${fpEnd})`],
  [`=MAX('Form Properties'!${alphaCol}5:${alphaCol}${fpEnd})`],
  [`=COUNTA('Model Summary'!A5:A${msEnd})`],
  [`=COUNTIF('Model Summary'!${modelConvergedCol}5:${modelConvergedCol}${msEnd},1)`],
  [`=COUNTIF('Item Decisions'!${itemTypeCol}5:${itemTypeCol}${idEnd},"binary")`],
];
summary.getRange("E5:E10").formulas = [
  [`=COUNTA('Link Coverage'!B5:B${lcEnd})`],
  [`=COUNTIF('Link Coverage'!${statusCol}5:${statusCol}${lcEnd},"at least 5 core/expanded candidates")`],
  [`=COUNTIF('Link Coverage'!${statusCol}5:${statusCol}${lcEnd},"fewer than 5 core/expanded candidates")`],
  [`=COUNTIF('Link Coverage'!${statusCol}5:${statusCol}${lcEnd},"no empirically eligible candidate")`],
  [`=COUNTIF('Link Coverage'!${statusCol}5:${statusCol}${lcEnd},"no common binary items")`],
  [`=COUNTIF('Anchor Candidates'!${tierCol}5:${tierCol}${acEnd},"Tier A core candidate")`],
];
summary.getRange("H5:H10").formulas = [
  [`=COUNTA('Item Decisions'!A5:A${idEnd})`],
  [`=COUNTA('Domain Completion'!A5:A${dmEnd})`],
  [`=COUNTIF('Domain Completion'!${domainConfirmCol}5:${domainConfirmCol}${dmEnd},1)`],
  [`=COUNTA('Grade Shift'!A5:A${shEnd})`],
  ["=COUNTA('French Forms'!A5:A10)"],
  [`=COUNTA('Blocking Issues'!A5:A${biEnd})`],
];
for (const r of ["A5:B10", "D5:E10", "G5:H10"]) summary.getRange(r).format = { borders: { preset: "outside", style: "thin", color: COLORS.border } };
for (const r of ["B5:B10", "E5:E10", "H5:H10"]) summary.getRange(r).format = { fill: COLORS.paleBlue, font: { bold: true, size: 12 }, numberFormat: "0.000" };

summary.mergeCells("A13:H13"); summary.getRange("A13").values = [["What the evidence says"]];
summary.getRange("A13:H13").format = { fill: COLORS.navy, font: { bold: true, color: COLORS.white, size: 12 } };
const findings = [
  "Reliability is consistently strong, but high alpha does not establish unidimensionality. Two baseline 2PL models did not converge and required Rasch fallback; local dependence is widespread and should be mapped to passages/tasks.",
  "The 33 required links are not equally supported: Arabic Grade 5 pre/post and Arabic Grades 4–5 are disconnected; three additional links have no empirically eligible candidate and twelve have fewer than five.",
  "The Ministry return completed 418 of 519 original rows. This package proposes the missing codes for all administered-grade rows, but 101 rows require Ministry confirmation because their values were inherited or rule-derived.",
  "French currently uses shared form pools. The recommendation is six grade-specific operational forms with controlled bridge anchors, not six isolated forms and not wholesale reuse of N23/N456.",
];
findings.forEach((text, i) => { const row = 14 + i * 2; summary.mergeCells(`A${row}:H${row + 1}`); summary.getRange(`A${row}`).values = [[text]]; summary.getRange(`A${row}:H${row + 1}`).format = { wrapText: true, fill: i % 2 ? COLORS.gray : COLORS.white, rowHeight: 34, verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: COLORS.border } }; });

summary.mergeCells("A23:H23"); summary.getRange("A23").values = [["Immediate decisions required"]];
summary.getRange("A23:H23").format = { fill: COLORS.blue, font: { bold: true, color: COLORS.white, size: 12 } };
const actions = [
  ["1", "Confirm/revise the 101 proposed domain classifications and approve grade-specific blueprint weights."],
  ["2", "Retain current eligible anchors and add only enough unchanged bank items to bring each deficient link to five candidates."],
  ["3", "Review every Tier A/B candidate against actual source-language prompts, stimuli, options, keys/rubrics, layout, scoring, and exposure before anchor approval."],
  ["4", "Assign stimulus_id/testlet_id/rubric_id and re-estimate after the proposed forms are assembled and piloted by school."],
];
summary.getRange("A24:H27").values = actions.map(x => [x[0], x[1], null, null, null, null, null, null]);
summary.getRange("A24:A27").format = { fill: COLORS.paleGold, font: { bold: true }, horizontalAlignment: "center" };
summary.getRange("B24:H27").merge(true); summary.getRange("B24:H27").format = { wrapText: true, rowHeight: 34, borders: { preset: "outside", style: "thin", color: COLORS.border } };
summary.getRange("A29:H31").merge(); summary.getRange("A29").values = [["Decision boundary: empirical quality, substantive necessity, and anchor eligibility are separate. No item is automatically dropped from a threshold, and no candidate becomes an operational anchor until full-version and exposure review is complete."]];
summary.getRange("A29:H31").format = { fill: COLORS.paleGold, font: { bold: true, color: COLORS.text }, wrapText: true, verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: "#C9A227" } };
summary.mergeCells("A33:H33"); summary.getRange("A33").values = [["Minimal-change pilot package"]];
summary.getRange("A33:H33").format = { fill: COLORS.blue, font: { bold: true, color: COLORS.white, size: 12 } };
summary.getRange("A34:A36").values = [["Mandatory replacements"], ["Conditional backups"], ["Shortlist rows"]];
summary.getRange("D34:D36").values = [["Links requiring repair"], ["Bank candidates added"], ["Links restored to ≥5"]];
summary.getRange("G34:G36").values = [["Forms needing tail repair"], ["Tail-only additions"], ["Forms already tail-adequate"]];
summary.getRange("B34:B36").formulas = [
  [`=COUNTIF('Action Shortlist'!${actionPriorityCol}5:${actionPriorityCol}${asEnd},"change now")`],
  [`=COUNTIF('Action Shortlist'!${actionPriorityCol}5:${actionPriorityCol}${asEnd},"conditional backup")`],
  [`=COUNTA('Action Shortlist'!A5:A${asEnd})`],
];
summary.getRange("E34:E36").formulas = [
  [`=COUNTA('Anchor Repairs'!A5:A${arEnd})`],
  [`=SUM('Anchor Repairs'!${anchorItemsAddedCol}5:${anchorItemsAddedCol}${arEnd})`],
  [`=COUNTIF('Anchor Repairs'!${anchorCandidateTotalCol}5:${anchorCandidateTotalCol}${arEnd},">=5")`],
];
summary.getRange("H34:H36").formulas = [
  [`=COUNTIF('Tail Coverage'!${tailStatusCol}5:${tailStatusCol}${tcEnd},"<>adequate after accepted revisions")`],
  [`=SUM('Tail Coverage'!${tailOnlyCol}5:${tailOnlyCol}${tcEnd})`],
  [`=COUNTIF('Tail Coverage'!${tailStatusCol}5:${tailStatusCol}${tcEnd},"adequate after accepted revisions")`],
];
for (const r of ["A34:B36", "D34:E36", "G34:H36"]) summary.getRange(r).format = { borders: { preset: "outside", style: "thin", color: COLORS.border } };
for (const r of ["B34:B36", "E34:E36", "H34:H36"]) summary.getRange(r).format = { fill: COLORS.paleGreen, font: { bold: true, size: 12 }, numberFormat: "0" };
summary.mergeCells("A38:H39"); summary.getRange("A38").values = [["Use the four compact sheets first. They preserve current items wherever possible, keep anchors unchanged, and place exact item text, answers, and surface-edit instructions in one protected pilot bank."]];
summary.getRange("A38:H39").format = { fill: COLORS.gray, font: { italic: true, color: COLORS.text }, wrapText: true, verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: COLORS.border } };
summary.getRange("A1:A39").format.columnWidth = 24; summary.getRange("B1:B39").format.columnWidth = 16;
summary.getRange("C1:C39").format.columnWidth = 3; summary.getRange("D1:D39").format.columnWidth = 25; summary.getRange("E1:E39").format.columnWidth = 16; summary.getRange("F1:F39").format.columnWidth = 3; summary.getRange("G1:G39").format.columnWidth = 25; summary.getRange("H1:H39").format.columnWidth = 16;
summary.freezePanes.freezeRows(2);

// README/protocol.
const readme = workbook.worksheets.add("README");
readme.showGridLines = false;
readme.mergeCells("A1:F1"); readme.getRange("A1").values = [["Workbook Guide & Decision Protocol"]];
readme.getRange("A1:F1").format = { fill: COLORS.navy, font: { bold: true, color: COLORS.white, size: 16 }, rowHeight: 28 };
const readmeRows = [
  ["Purpose", "Human-review package for Year 3 item quality, anchors, domain completion, one-grade shifting, and next-form design."],
  ["Scope", "Wave-specific baseline, pilot, and endline files only. The combined Y1–Y3 file is reconciliation-only; inherited code was not opened or executed."],
  ["Treatment", "Treatment assignment was removed/ignored for item selection and anchor screening. Treatment-related DIF is a later sensitivity after decisions are frozen."],
  ["Scoring", "Binary: 1 correct, 0 incorrect, tagged missing = don't know, untagged blank = nonresponse. Primary raw score counts correct and scores all noncorrect responses zero. Continuous fluency/rubric fields are separate."],
  ["Duplicates", "Within wave × subject × administered grade × panel ID: retain most mapped responses, then longest duration, then earliest source row. Identifiers are never exported."],
  ["Models", "Pilot uses Rasch fallback only. Baseline/endline compare Rasch and 2PL; 2PL is primary only when converged. School split is by school, not individual."],
  ["Thresholds", "All numerical criteria are warning flags for review, never automatic keep/drop rules."],
  ["Anchor rule", "Prompt-summary match + endpoint quality + no material clustered DIF warning. Operational equivalence and exposure review remain mandatory."],
  ["Start here", "Use Action Shortlist, Anchor Repairs, Tail Coverage, and Pilot Item Bank first. These are the compact minimal-change sheets."],
  ["Ministry edit columns", "Use the yellow decision/comment columns on the compact sheets or Item Decisions. Do not overwrite empirical columns."],
];
readme.getRange("A3:B12").values = readmeRows;
readme.getRange("A3:A12").format = { fill: COLORS.paleBlue, font: { bold: true }, verticalAlignment: "top" };
readme.getRange("B3:B12").format = { wrapText: true, verticalAlignment: "top" };
readme.getRange("A3:B12").format.borders = { preset: "all", style: "thin", color: COLORS.border };
readme.getRange("A1:A12").format.columnWidth = 24; readme.getRange("B1:B12").format.columnWidth = 90;

writeDataSheet(workbook, "Action Shortlist", "Minimal Replacement Shortlist", "Only five items are proposed for replacement now; six additional rows are conditional backups. Historical evidence supports a pilot shortlist, not automatic reuse.", actionShortlist, { freezeColumns: 4 });
writeDataSheet(workbook, "Anchor Repairs", "Minimal Anchor Repair Plan", "Retain every current eligible anchor. Add only enough historically strong candidates to reach five per deficient link; pre/post repairs apply prospectively because collected Year 3 waves cannot be changed.", anchorRepairs, { freezeColumns: 3 });
writeDataSheet(workbook, "Tail Coverage", "Tail Coverage Check", "Minimum design check: at least two non-extreme easy items and two non-extreme hard items per form. Reuse anchor/replacement items before adding any tail-only item.", tailCoverage, { freezeColumns: 2 });
writeDataSheet(workbook, "Pilot Item Bank", "Protected Pilot Item Bank", "Anchors are unchanged. The two surface-edit columns are populated by our team for Maths; French and Arabic remain for Ministry adaptation. Rows are not send-ready until the item text and answer/rubric status are complete.", pilotItemBank, { freezeColumns: 4 });
workbook.worksheets.getItem("Pilot Item Bank").getRange(`A5:K${4 + pilotItemBank.rows.length}`).format.rowHeight = 42;
writeDataSheet(workbook, "Form Properties", "Form-Level Psychometric Properties", "Reliability intervals use 200 school-cluster bootstrap replicates. Fit statistics are for the primary converged model; alpha does not establish unidimensionality.", formProperties, { freezeColumns: 3 });
writeDataSheet(workbook, "Link Coverage", "Required Link Coverage", "All 33 intended within-grade pre/post and adjacent-grade links, including disconnected and empirically unsupported links.", anchorCoverage, { freezeColumns: 3 });
writeDataSheet(workbook, "Item Decisions", "Ministry Item Decisions", "Provisional evidence-based dispositions. Yellow columns are for Ministry final decisions/comments. Secure item summaries are included because this workbook is stored only in the protected work_root.", itemDecisions, { freezeColumns: 4, appendDecisionColumns: true });
writeDataSheet(workbook, "Anchor Candidates", "Within-Year Anchor Candidate Evidence", "Treatment-blind logistic DIF conditions on the common-item rest score with school-clustered standard errors. Tier is link-specific and still requires full-version/exposure review.", anchorCandidates, { freezeColumns: 4 });
writeDataSheet(workbook, "Anchor Sensitivity", "Anchor-Set Sensitivity", "Mean–sigma link constants and parameter agreement for core, expanded, and all empirically eligible sets. Rows with <3 parameters remain unestimated.", anchorSensitivity, { freezeColumns: 3 });
writeDataSheet(workbook, "Trend Anchors", "Provisional Across-Year Trend Candidates", "Compiled latest-item IDs and prompt-summary hashes do not establish a common scale. Y1/Y2 response-data and full-version validation remain pending.", trendCandidates, { freezeColumns: 4 });
writeDataSheet(workbook, "Domain Completion", "Completed Content & Cognitive Domain Map", "All 639 item×administered-grade rows are populated. The source/confidence columns identify 101 values requiring Ministry confirmation.", domains, { freezeColumns: 4 });
writeDataSheet(workbook, "Grade Shift", "Proposed One-Grade Baseline Shift", "Grade 1 uses current baseline Grade 1; target baseline Grades 2–6 inherit source endline Grades 1–5. Every row requires target-grade piloting and blueprint approval.", shiftMap, { freezeColumns: 4 });
writeDataSheet(workbook, "French Forms", "French Grade-Specific Form Redesign", "Six separate operational forms with controlled bridge anchors. Current shared pools are evidence sources, not the final grade-specific design.", frenchForms, { freezeColumns: 1 });
writeDataSheet(workbook, "Model Summary", "IRT Model Diagnostics", "Rasch and 2PL comparisons where justified; pilot uses Rasch fallback. Two baseline 2PL fits did not converge and are retained as evidence, not forced.", modelSummary, { freezeColumns: 3 });
writeDataSheet(workbook, "Instrument Advice", "Instrument Development Advice", "Priority actions required before the next form is frozen and fielded.", advice, { freezeColumns: 1 });
writeDataSheet(workbook, "Blocking Issues", "Blocking & Confirmation Issues", "Open issues are preserved with scientific consequence and provisional action. PII cleanup remains team-owned and excluded from this analysis.", blockingIssues, { freezeColumns: 4 });
writeDataSheet(workbook, "Source Registry", "Year 3 Source Registry", "Root aliases and relative paths only. SHA-256 hashes identify exact candidates; archive/conflicted/PII-like files are excluded with a reason.", sourceRegistry, { freezeColumns: 4 });

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

// Compact verification before export.
const summaryInspect = await workbook.inspect({ kind: "table", range: "Executive Summary!A1:H39", include: "values,formulas", tableMaxRows: 39, tableMaxCols: 8, maxChars: 15000 });
await fs.writeFile(path.join(previewDir, "inspect_summary.ndjson"), summaryInspect.ndjson);
const errors = await workbook.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 300 }, summary: "final formula error scan" });
await fs.writeFile(path.join(previewDir, "formula_errors.ndjson"), errors.ndjson);

for (const sheetName of ["Executive Summary", "README", "Action Shortlist", "Anchor Repairs", "Tail Coverage", "Pilot Item Bank", "Form Properties", "Link Coverage", "Item Decisions", "Anchor Candidates", "Anchor Sensitivity", "Trend Anchors", "Domain Completion", "Grade Shift", "French Forms", "Model Summary", "Instrument Advice", "Blocking Issues", "Source Registry"]) {
  const sheet = workbook.worksheets.getItem(sheetName);
  const preview = await workbook.render({ sheetName, range: sheetName === "Executive Summary" ? "A1:H39" : "A1:O20", autoCrop: "all", scale: 0.75, format: "png" });
  await fs.writeFile(path.join(previewDir, `${sheetName.replace(/[^A-Za-z0-9]+/g, "_")}.png`), new Uint8Array(await preview.arrayBuffer()));
}
const pilotBankFullPreview = await workbook.render({ sheetName: "Pilot Item Bank", range: "A4:K46", autoCrop: "all", scale: 0.75, format: "png" });
await fs.writeFile(path.join(previewDir, "Pilot_Item_Bank_All.png"), new Uint8Array(await pilotBankFullPreview.arrayBuffer()));

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
console.log(JSON.stringify({ outputPath, sheets: workbook.worksheets.items.map(s => s.name), previewDir }));
