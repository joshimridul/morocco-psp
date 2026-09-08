import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const [sourceCsv, outputPath, previewDir] = process.argv.slice(2);
if (!sourceCsv || !outputPath || !previewDir) {
  throw new Error(
    "Usage: node build_half_baseline_item_map.mjs <source.csv> <output.xlsx> <preview-dir>",
  );
}

const COLORS = {
  navy: "#17365D",
  blue: "#2E75B6",
  paleBlue: "#D9EAF7",
  paleGreen: "#E2F0D9",
  paleGold: "#FFF2CC",
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

const matrix = parseCsv(await fs.readFile(sourceCsv, "utf8"));
if (matrix.length !== 333) {
  throw new Error(`Expected 332 selected rows plus header; found ${matrix.length}.`);
}

const sourceHeaders = matrix[0];
const requiredHeaders = [
  "subject",
  "baseline_grade",
  "baseline_item_no",
  "item_id",
  "selected_anchor",
  "item_or_summary",
  "content_domain",
  "cognitive_domain",
  "source",
];
for (const header of requiredHeaders) {
  if (!sourceHeaders.includes(header)) throw new Error(`Missing source column: ${header}`);
}
const records = matrix.slice(1).map((row) =>
  Object.fromEntries(sourceHeaders.map((header, index) => [header, row[index] ?? ""])),
);

const headers = [
  "Subject",
  "Baseline grade",
  "Item no.",
  "Item ID",
  "Anchor",
  "Item / summary",
  "Content domain",
  "Cognitive domain",
  "Source",
];
const rows = records.map((row) => [
  row.subject,
  Number(row.baseline_grade),
  Number(row.baseline_item_no),
  row.item_id,
  row.selected_anchor === "1" ? "YES" : "",
  row.item_or_summary,
  row.content_domain,
  row.cognitive_domain,
  row.source,
]);

const workbook = Workbook.create();
const sheet = workbook.worksheets.add("Baseline Item Map");
sheet.showGridLines = false;
const lastCol = colLetter(headers.length - 1);
const headerRow = 4;
const firstDataRow = 5;
const endRow = firstDataRow + rows.length - 1;

sheet.mergeCells(`A1:${lastCol}1`);
sheet.getRange("A1").values = [["Half-Length Baseline Selection Map - Draft"]];
sheet.getRange(`A1:${lastCol}1`).format = {
  fill: COLORS.navy,
  font: { bold: true, color: COLORS.white, size: 16 },
  rowHeight: 30,
  verticalAlignment: "center",
};

sheet.mergeCells(`A2:${lastCol}2`);
sheet.getRange("A2").values = [[
  "Baseline Grade 1 uses the prior Grade 1 baseline; Grades 2-6 use the prior endline for the grade immediately below. Anchor = YES means copy the exact source version unchanged. Confirm shared passages, images, rubrics and source-language scoring when assembling the final booklets.",
]];
sheet.getRange(`A2:${lastCol}2`).format = {
  fill: COLORS.paleBlue,
  font: { color: COLORS.text, size: 10 },
  wrapText: true,
  rowHeight: 40,
  verticalAlignment: "center",
};

sheet.getRange(`A${headerRow}:${lastCol}${endRow}`).values = [headers, ...rows];
sheet.getRange(`A${headerRow}:${lastCol}${headerRow}`).format = {
  fill: COLORS.blue,
  font: { bold: true, color: COLORS.white, size: 9 },
  wrapText: true,
  rowHeight: 34,
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

const widths = [12, 12, 9, 18, 10, 54, 22, 20, 34];
widths.forEach((width, index) => {
  const letter = colLetter(index);
  sheet.getRange(`${letter}1:${letter}${endRow}`).format.columnWidth = width;
});

const table = sheet.tables.add(`A${headerRow}:${lastCol}${endRow}`, true, "BaselineItemMapTable");
table.style = "TableStyleMedium2";
table.showBandedRows = true;
table.showFilterButton = true;

sheet.getRange(`E${firstDataRow}:E${endRow}`).conditionalFormats.add("containsText", {
  text: "YES",
  format: { fill: COLORS.paleGreen, font: { bold: true, color: COLORS.text } },
});
sheet.getRange(`A${headerRow}:${lastCol}${endRow}`).format.autofitRows();
sheet.freezePanes.freezeRows(headerRow);
sheet.freezePanes.freezeColumns(5);

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

for (const check of [
  { range: "Baseline Item Map!A1:I18", maxRows: 18 },
  { range: `Baseline Item Map!A${endRow - 12}:I${endRow}`, maxRows: 13 },
]) {
  const inspected = await workbook.inspect({
    kind: "table",
    range: check.range,
    include: "values,formulas",
    tableMaxRows: check.maxRows,
    tableMaxCols: 9,
    maxChars: 12000,
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
  { name: "baseline-map-overview", range: `A1:I${endRow}`, scale: 0.24 },
  { name: "baseline-map-top", range: "A1:I18", scale: 1.0 },
  { name: "baseline-map-middle", range: "A160:I178", scale: 1.0 },
  { name: "baseline-map-bottom", range: `A${endRow - 16}:I${endRow}`, scale: 1.0 },
]) {
  const preview = await workbook.render({
    sheetName: "Baseline Item Map",
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
console.log(JSON.stringify({ outputPath, sheetCount: 1, itemRows: rows.length }));
