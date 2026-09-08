import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const [workRoot, outputPath, previewDir] = process.argv.slice(2);
if (!workRoot || !outputPath || !previewDir) {
  throw new Error(
    "Usage: node build_simple_ministry_sheet.mjs <workRoot> <output.xlsx> <previewDir>",
  );
}

const COLORS = {
  navy: "#17365D",
  blue: "#2E75B6",
  paleBlue: "#D9EAF7",
  paleGreen: "#E2F0D9",
  paleGold: "#FFF2CC",
  paleRed: "#FCE4D6",
  gray: "#F3F4F6",
  border: "#D0D7DE",
  text: "#1F2937",
  white: "#FFFFFF",
};

function parseCsv(text) {
  text = text.replace(/^\uFEFF/, "");
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
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }
  if (field.length || row.length) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }
  return rows.filter((values) => values.some((value) => value !== ""));
}

async function readCsv(relativePath) {
  const matrix = parseCsv(await fs.readFile(path.join(workRoot, relativePath), "utf8"));
  const headers = matrix[0];
  return matrix.slice(1).map((row) =>
    Object.fromEntries(headers.map((header, index) => [header, row[index] ?? ""])),
  );
}

function rowKey(row, gradeField) {
  return [
    row.subject,
    row[gradeField],
    row.form_group,
    row.item_id,
    row.scto_question_id,
    row.question_number,
  ].join("|");
}

function idKey(row) {
  return `${row.subject}|${String(row.item_id).trim().toLowerCase()}`;
}

function normalizeText(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function isAnchorRecommendation(value) {
  return value.startsWith("provisional anchor") || value.startsWith("reserve anchor");
}

function simplifyRecommendation(value) {
  if (value.startsWith("provisional anchor")) return "Include unchanged";
  if (value.startsWith("reserve anchor")) return "Include unchanged";
  if (value === "revise or replace, then re-pilot") return "Replace before pilot";
  if (value === "retain only after psychometric review and re-pilot") {
    return "Review; replace if not acceptable";
  }
  if (value === "revise administration/wording/scoring, then re-pilot") {
    return "Revise before pilot";
  }
  if (value.startsWith("retain as scored non-anchor")) {
    return value.includes("testlet")
      ? "Keep with its passage or shared task"
      : "Keep";
  }
  if (value.startsWith("diagnostic")) return "Keep as a separate fluency or rubric score";
  return value;
}

function suggestedRevision(frozen, mathEdit) {
  if (frozen) return "";
  if (mathEdit?.revised_item_english) {
    const visual = mathEdit.visual_or_layout_edit_required?.startsWith("YES")
      ? " | Update artwork/layout"
      : "";
    const bundle = mathEdit.testlet_or_bundle
      ? ` | Update together: ${mathEdit.testlet_or_bundle}`
      : "";
    return `${mathEdit.revised_item_english} | Answer: ${mathEdit.revised_answer_or_key}${visual}${bundle}`;
  }
  return "";
}

function exactAnswer(decision, addition, mathEdit) {
  if (mathEdit?.current_answer_or_key) return mathEdit.current_answer_or_key;
  if (
    addition
    && normalizeText(addition.item_text) === normalizeText(decision.question_summary)
    && addition.correct_answer_or_guideline
  ) {
    return addition.correct_answer_or_guideline;
  }
  return decision.item_type === "binary"
    ? "TO VERIFY FROM EXAMINER GUIDE"
    : "TO VERIFY RUBRIC / SCORING GUIDE";
}

function joinGrades(values) {
  const grades = [...values].sort((a, b) => a - b);
  if (grades.length === 1) return `Grade ${grades[0]}`;
  if (grades.length === 2) return `Grades ${grades[0]} and ${grades[1]}`;
  return `Grades ${grades.slice(0, -1).join(", ")}, and ${grades.at(-1)}`;
}

function plainMinistryAction(row, replacements, tailDirections) {
  const roleParts = row.proposed_role.split(";").map((part) => part.trim());
  const anchorParts = roleParts.filter((part) => part.startsWith("anchor:"));
  const anchorGrades = new Set();
  const repeatedGrades = new Set();
  for (const role of anchorParts) {
    const pair = role.match(/ G([1-6])–G([1-6])/);
    if (pair) {
      anchorGrades.add(Number(pair[1]));
      anchorGrades.add(Number(pair[2]));
    }
    const repeated = role.match(/ G([1-6]) pre\/post/);
    if (repeated) repeatedGrades.add(Number(repeated[1]));
  }

  const sentences = [];
  if (anchorGrades.size) {
    sentences.push(`Include unchanged in ${joinGrades(anchorGrades)}.`);
  }
  if (repeatedGrades.size) {
    const grades = [...repeatedGrades].sort((a, b) => a - b);
    sentences.push(
      grades.length === 1
        ? `Use unchanged in both the Grade ${grades[0]} baseline and endline assessments.`
        : `Use unchanged in the baseline and endline assessments for ${joinGrades(repeatedGrades)}.`,
    );
  }

  const replacement = replacements.get(idKey(row));
  if (roleParts.includes("replacement now") && replacement) {
    sentences.push(
      `${anchorParts.length ? "It should also replace" : "Use now to replace"} ${replacement.current_item} in Grade ${replacement.grade}.`,
    );
  }
  if (roleParts.includes("conditional replacement") && replacement) {
    sentences.push(
      anchorParts.length
        ? `It may also replace ${replacement.current_item} in Grade ${replacement.grade} if needed.`
        : `Do not include now. Use in Grade ${replacement.grade} only if ${replacement.current_item} is removed.`,
    );
  }

  if (roleParts.includes("tail support")) {
    const direction = tailDirections.get(idKey(row))
      || (normalizeText(row.suggested_surface_change).includes("easier") ? "easier" : "additional");
    if (row.item_id === "TO BE SELECTED") {
      sentences.push(
        `Please provide one ${direction} Grade ${row.target_grade} ${row.subject} item, with its correct answer or scoring rule.`,
      );
    } else if (row.item_id === "m2140_nv") {
      sentences.push("Use the revised version in Grade 6 as an easier Maths item.");
    } else {
      const article = /^[aeiou]/i.test(direction) ? "an" : "a";
      sentences.push(`Add to Grade ${row.target_grade} as ${article} ${direction} ${row.subject} item.`);
    }
  }

  return sentences.join(" ") || "Please review and confirm whether to use this item.";
}

function answerForAddition(row) {
  if (row.review_status === "item and answer required") {
    return "[MINISTRY TO PROVIDE ITEM AND ANSWER]";
  }
  if (row.review_status === "answer/rubric confirmation required") {
    const existing = row.revised_answer || row.correct_answer_or_guideline;
    return existing
      ? `${existing} [MINISTRY TO CONFIRM]`
      : "[MINISTRY TO CONFIRM ANSWER / SCORING RULE]";
  }
  return row.revised_answer || row.correct_answer_or_guideline || "[MINISTRY TO PROVIDE]";
}

function colLetter(index) {
  let number = index + 1;
  let result = "";
  while (number > 0) {
    number -= 1;
    result = String.fromCharCode(65 + (number % 26)) + result;
    number = Math.floor(number / 26);
  }
  return result;
}

function writeSheet(workbook, config) {
  const {
    name,
    title,
    note,
    headers,
    rows,
    widths,
    tableName,
    freezeColumns,
    editableStartIndex,
    validationColumnIndex,
    conditionalRules,
  } = config;
  const sheet = workbook.worksheets.add(name);
  sheet.showGridLines = false;
  const lastCol = colLetter(headers.length - 1);
  const headerRow = 4;
  const firstDataRow = 5;
  const endRow = firstDataRow + rows.length - 1;

  sheet.mergeCells(`A1:${lastCol}1`);
  sheet.getRange("A1").values = [[title]];
  sheet.getRange(`A1:${lastCol}1`).format = {
    fill: COLORS.navy,
    font: { bold: true, color: COLORS.white, size: 16 },
    rowHeight: 30,
    verticalAlignment: "center",
  };

  sheet.mergeCells(`A2:${lastCol}2`);
  sheet.getRange("A2").values = [[note]];
  sheet.getRange(`A2:${lastCol}2`).format = {
    fill: COLORS.paleBlue,
    font: { color: COLORS.text, size: 10 },
    wrapText: true,
    rowHeight: 46,
    verticalAlignment: "center",
  };

  sheet.getRange(`A${headerRow}:${lastCol}${endRow}`).values = [headers, ...rows];
  sheet.getRange(`A${headerRow}:${lastCol}${headerRow}`).format = {
    fill: COLORS.blue,
    font: { bold: true, color: COLORS.white, size: 9 },
    wrapText: true,
    rowHeight: 38,
    verticalAlignment: "center",
    horizontalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: COLORS.border },
  };
  sheet.getRange(`A${firstDataRow}:${lastCol}${endRow}`).format = {
    font: { color: COLORS.text, size: 9 },
    wrapText: true,
    verticalAlignment: "top",
    borders: { insideHorizontal: { style: "thin", color: "#E5E7EB" } },
  };

  widths.forEach((width, index) => {
    const letter = colLetter(index);
    sheet.getRange(`${letter}1:${letter}${endRow}`).format.columnWidth = width;
  });

  const table = sheet.tables.add(`A${headerRow}:${lastCol}${endRow}`, true, tableName);
  table.style = "TableStyleMedium2";
  table.showBandedRows = true;
  table.showFilterButton = true;

  if (editableStartIndex !== undefined) {
    const start = colLetter(editableStartIndex);
    sheet.getRange(`${start}${firstDataRow}:${lastCol}${endRow}`).format.fill = COLORS.paleGold;
  }
  if (validationColumnIndex !== undefined) {
    const validationCol = colLetter(validationColumnIndex);
    sheet.getRange(`${validationCol}${firstDataRow}:${validationCol}${endRow}`).dataValidation = {
      rule: {
        type: "list",
        values: ["Approve", "Revise", "Confirm domain", "Replace", "Hold", "Discuss"],
      },
    };
  }

  for (const rule of conditionalRules ?? []) {
    const range = sheet.getRange(
      `${colLetter(rule.column)}${firstDataRow}:${colLetter(rule.column)}${endRow}`,
    );
    range.conditionalFormats.add("containsText", {
      text: rule.text,
      format: rule.format,
    });
  }

  sheet.getRange(`A${headerRow}:${lastCol}${endRow}`).format.autofitRows();
  sheet.freezePanes.freezeRows(headerRow);
  sheet.freezePanes.freezeColumns(freezeColumns);
  return { sheet, headerRow, firstDataRow, endRow, lastCol };
}

const decisions = await readCsv("outputs/y3_ministry/03_forms/y3_ministry_item_decisions.csv");
const domains = await readCsv("outputs/y3_ministry/03_forms/y3_completed_domain_map.csv");
const additions = await readCsv("outputs/y3_ministry/03_forms/y3_pilot_item_bank.csv");
const mathEdits = await readCsv("private_manifests/y3_math_surface_edits.csv");
const replacementActions = await readCsv("outputs/y3_ministry/03_forms/y3_minimal_replacement_actions.csv");
const tailCoverage = await readCsv("outputs/y3_ministry/03_forms/y3_tail_coverage_check.csv");

if (decisions.length !== 639 || domains.length !== 639 || additions.length !== 42 || mathEdits.length !== 138) {
  throw new Error(
    `Unexpected source counts: decisions=${decisions.length}, domains=${domains.length}, additions=${additions.length}, mathEdits=${mathEdits.length}`,
  );
}

const domainByKey = new Map(domains.map((row) => [rowKey(row, "form_grade"), row]));
const additionById = new Map(additions.map((row) => [idKey(row), row]));
const mathEditByKey = new Map(mathEdits.map((row) => [rowKey(row, "administered_grade"), row]));
const replacementByCandidate = new Map();
for (const row of replacementActions) {
  const candidate = row.primary_candidate.split(" — ", 1)[0].trim();
  if (candidate) {
    replacementByCandidate.set(idKey({ subject: row.subject, item_id: candidate }), row);
  }
}
const tailDirectionByCandidate = new Map();
for (const row of tailCoverage) {
  const minimum = Number(row.minimum_each_tail);
  const directions = [];
  if (Number(row.good_easy_items_current) < minimum) directions.push("easier");
  if (Number(row.good_hard_items_current) < minimum) directions.push("harder");
  const direction = directions.join(" and ") || "additional";
  for (const candidate of row.proposed_items_for_tail_coverage.split(", ").filter(Boolean)) {
    tailDirectionByCandidate.set(idKey({ subject: row.subject, item_id: candidate }), direction);
  }
  if (row.status === "Ministry item adaptation required") {
    tailDirectionByCandidate.set(
      idKey({ subject: row.subject, item_id: "TO BE SELECTED" }),
      direction,
    );
  }
}
const fullHeaders = [
  "Subject",
  "Grade",
  "Form",
  "Item ID",
  "Question no.",
  "Anchor",
  "Current item / summary",
  "Current answer / key",
  "Content domain",
  "Cognitive domain",
  "Confirm domains?",
  "What we recommend",
  "Suggested revision",
  "Ministry response / final wording and answer",
];

const fullRows = decisions.map((decision) => {
  const domain = domainByKey.get(rowKey(decision, "administered_grade"));
  if (!domain) throw new Error(`Missing domain row for ${rowKey(decision, "administered_grade")}`);
  // Anchor status belongs to this administered item-version row, not to the item ID globally.
  // The same ID can recur in another grade/form without serving as an anchor there.
  const frozen = isAnchorRecommendation(decision.provisional_recommendation);
  const addition = additionById.get(idKey(decision));
  const mathEdit = mathEditByKey.get(rowKey(decision, "administered_grade"));
  return [
    decision.subject,
    Number(decision.administered_grade),
    decision.form_group,
    decision.item_id,
    decision.question_number,
    frozen ? "YES" : "",
    decision.question_summary,
    exactAnswer(decision, addition, mathEdit),
    domain.proposed_content_domain,
    domain.proposed_cognitive_domain,
    domain.requires_ministry_confirmation === "1" ? "YES" : "",
    frozen ? "Include unchanged" : simplifyRecommendation(decision.provisional_recommendation),
    suggestedRevision(frozen, mathEdit),
    "",
  ];
});

fullRows.sort((a, b) =>
  a[0].localeCompare(b[0])
  || a[1] - b[1]
  || String(a[2]).localeCompare(String(b[2]))
  || Number(a[4] || 999) - Number(b[4] || 999)
  || String(a[3]).localeCompare(String(b[3])),
);

const additionHeaders = [
  "Subject",
  "Grade(s)",
  "Item ID",
  "What to do",
  "Candidate item",
  "Correct answer / key",
  "Source bank",
  "Suggested surface change",
  "Change made by our team",
  "Revised answer",
  "Ministry decision",
  "Ministry final edit / answer / comment",
];

const additionRows = additions.map((row) => [
  row.subject,
  row.target_grade,
  row.item_id,
  plainMinistryAction(row, replacementByCandidate, tailDirectionByCandidate),
  row.item_text || "[MINISTRY TO SELECT ONE EASY GRADE 4 FRENCH ITEM]",
  answerForAddition(row),
  row.source_bank,
  row.suggested_surface_change || "None.",
  row.change_made || (row.proposed_role.includes("anchor:") ? "None - anchor frozen." : "For Ministry to complete"),
  row.revised_answer,
  "",
  "",
]);

additionRows.sort((a, b) =>
  a[0].localeCompare(b[0])
  || Number(String(a[1]).match(/\d+/)?.[0] ?? 99) - Number(String(b[1]).match(/\d+/)?.[0] ?? 99)
  || String(a[2]).localeCompare(String(b[2])),
);

const workbook = Workbook.create();
const fullSheet = writeSheet(workbook, {
  name: "Full Year 3 Item Bank",
  title: "Full Year 3 Item Bank",
  note:
    "Anchor = YES means this item in this grade and form must be included unchanged. Suggested revision shows a Maths revision where we have proposed one. Confirm domains? = YES marks classifications we filled because they were missing. Please write only in the final yellow column.",
  headers: fullHeaders,
  rows: fullRows,
  widths: [12, 8, 10, 18, 11, 10, 48, 28, 18, 18, 18, 28, 52, 52],
  tableName: "FullYear3ItemBankTable",
  freezeColumns: 6,
  editableStartIndex: 13,
  conditionalRules: [
    { column: 5, text: "YES", format: { fill: COLORS.paleGreen, font: { bold: true, color: COLORS.text } } },
    { column: 10, text: "YES", format: { fill: COLORS.paleGold, font: { bold: true, color: COLORS.text } } },
    { column: 11, text: "Replace before pilot", format: { fill: COLORS.paleRed, font: { bold: true, color: COLORS.text } } },
    { column: 7, text: "TO VERIFY", format: { fill: COLORS.paleRed, font: { bold: true, color: COLORS.text } } },
  ],
});

const additionsSheet = writeSheet(workbook, {
  name: "Proposed Additions",
  title: "Items to Include, Replace or Confirm",
  note:
    "The What to do column gives one direct instruction for each row. Include every item that says unchanged, add, or use now. Do not include a2203 unless a525y3_nv3 is removed. Complete only the two yellow columns.",
  headers: additionHeaders,
  rows: additionRows,
  widths: [12, 10, 18, 54, 52, 28, 30, 40, 48, 28, 20, 48],
  tableName: "ProposedAdditionsTable",
  freezeColumns: 4,
  editableStartIndex: 10,
  validationColumnIndex: 10,
  conditionalRules: [
    { column: 3, text: "unchanged", format: { fill: COLORS.paleGreen, font: { bold: true, color: COLORS.text } } },
    { column: 3, text: "Use now to replace", format: { fill: COLORS.paleRed, font: { bold: true, color: COLORS.text } } },
    { column: 3, text: "Do not include now", format: { fill: COLORS.paleGold, font: { bold: true, color: COLORS.text } } },
    { column: 5, text: "MINISTRY TO", format: { fill: COLORS.paleRed, font: { bold: true, color: COLORS.text } } },
  ],
});

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

for (const check of [
  { range: `Full Year 3 Item Bank!A1:N12`, rows: 12, cols: 14 },
  { range: `Proposed Additions!A1:L15`, rows: 15, cols: 12 },
]) {
  const inspected = await workbook.inspect({
    kind: "table",
    range: check.range,
    include: "values,formulas",
    tableMaxRows: check.rows,
    tableMaxCols: check.cols,
    maxChars: 9000,
  });
  console.log(inspected.ndjson);
}

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan",
});
console.log(errors.ndjson);

for (const render of [
  { name: "full-overview", sheetName: "Full Year 3 Item Bank", range: `A1:N${fullSheet.endRow}`, scale: 0.22 },
  { name: "full-top", sheetName: "Full Year 3 Item Bank", range: "A1:N18", scale: 1.0 },
  { name: "full-middle", sheetName: "Full Year 3 Item Bank", range: "A310:N330", scale: 1.0 },
  { name: "full-bottom", sheetName: "Full Year 3 Item Bank", range: `A625:N${fullSheet.endRow}`, scale: 1.0 },
  { name: "additions-full", sheetName: "Proposed Additions", range: `A1:L${additionsSheet.endRow}`, scale: 0.75 },
]) {
  const preview = await workbook.render({
    sheetName: render.sheetName,
    range: render.range,
    scale: render.scale,
    format: "png",
  });
  await fs.writeFile(
    path.join(previewDir, `${render.name}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
console.log(JSON.stringify({
  outputPath,
  sheetCount: 2,
  fullRows: fullRows.length,
  distinctCurrentItemIds: new Set(decisions.map(idKey)).size,
  additions: additionRows.length,
  completedNonAnchorMathRows: mathEdits.length,
  completedNonAnchorMathIds: new Set(mathEdits.map(idKey)).size,
}));
