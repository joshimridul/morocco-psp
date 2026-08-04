# Data Package Checklist

## Required to begin

- [ ] Deidentified item-level student responses from every relevant previous wave
- [ ] Stable pseudonymous student ID where longitudinal linkage is needed
- [ ] School, class/cohort, grade, subject, year, wave, and form identifiers
- [ ] Raw response and scored response for each item
- [ ] Item maximum score and response format
- [ ] Missing/not-reached/invalid-response codes
- [ ] Original reported total and subscore variables for score tie-out
- [ ] Item map for each form and version
- [ ] Actual original-language prompts, passages, images, and response options
- [ ] Answer keys and scoring rubrics
- [ ] Administration instructions and time limits
- [ ] Item/version change log
- [ ] Existing anchor designations and their intended link role
- [ ] Domain definitions and official curriculum objective mapping

## Strongly recommended

- [ ] Item response times or page/task timing
- [ ] Rater ID and raw criterion-level ratings for oral/written tasks
- [ ] Test administrator and administration-mode indicators
- [ ] Treatment assignment and randomization block/unit
- [ ] Student demographic and language variables approved for analysis
- [ ] Sampling weights
- [ ] Attendance/attrition indicators
- [ ] Prior item statistics and analysis code
- [ ] Pilot notes, incident reports, and known scoring corrections
- [ ] Information on whether students received item feedback or answer exposure

## Privacy and governance

- [ ] Names, national identifiers, contact details, exact addresses, and unnecessary free text removed
- [ ] Stable pseudonymous IDs used for linkage
- [ ] Data-sharing agreement permits the intended analysis environment
- [ ] Raw data excluded from Git and any unapproved cloud repository

## Dropbox/GitHub boundary

- [ ] Every required source is referenced from Dropbox through a root alias and relative path
- [ ] A SHA-256 and provenance status are recorded for every selected source
- [ ] A dedicated Dropbox working root exists for derived data and data-bearing outputs
- [ ] New code contains tested guards preventing writes to the Y1, Y2, and Y3 legacy roots
- [ ] No legacy script will be executed until a separate static audit is authorized and complete
