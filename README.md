# CareLoop Clinics — No-Show Guard

Repository: https://github.com/balajiharish75/care_loop

Identify outpatient appointments likely to be missed, understand where and when
no-shows happen, extract reasons from call-centre notes, and recommend practical
interventions. The project connects four stages: data foundations (Python), SQL
business analysis, machine-learning risk prediction, and GenAI-assisted note
classification. The output of each stage feeds the next.

## Business Problem

Outpatient no-shows waste clinical slots, reduce revenue, and delay patient
care. CareLoop needs to flag, before the appointment day, which bookings are at
risk of being missed, understand the reasons patients give when they cancel or
skip, and prioritize where the call centre should intervene. This project builds
that capability from raw appointment, clinic, and follow-up-note data.

## Project Workflow

Four connected stages:

1. **Data foundations** (`notebooks/01_ingest_clean.ipynb`): ingest
   `appointments.csv` with Python's `csv` module, validate and clean with pandas,
   handle outliers, engineer features, enrich clinics with Open-Meteo forecast
   temperature, and export cleaned data plus a SQL loading script.
2. **SQL analysis** (`sql/02_queries.sql`): create the MySQL 8 database, load the
   data, and run five queries — no-show rate by clinic, booking lead-time bands,
   monthly trend with month-over-month change, and clinic ranking within cities.
3. **Machine learning** (`notebooks/03_model.ipynb`): predict no-show risk with
   logistic regression, decision trees, and random forest; select the model on
   cross-validation only (training data); tune the decision threshold on
   out-of-fold predictions; report once on the held-out test set.
4. **GenAI note classification** (`notebooks/04_genai.ipynb`): classify the
   first ten call-centre notes with Google Gemini Flash using structured JSON
   output, validate responses with Pydantic, skip blank notes without an API
   call, compare two prompts, and merge reasons back to appointments.

The Gemini API key is entered interactively at runtime (`input()`); it is never
stored in any file.

## Key Findings

1. **Data foundations:** 1,020 appointments ingested; 32 rejected (12 blank age,
   20 blank distance); 990 cleaned appointments and 8 clinics retained. Overall
   no-show rate is 22.0% (218 of 990).
2. **SQL analysis:** Hadapsar Care Centre has the highest no-show rate among
   clinics with at least 95 appointments: 27.3% (39 of 143). Gomti Nagar Care
   Point shows 33.3% but only 90 appointments, so it is flagged as small-sample
   rather than ranked highest. Appointments booked 31+ days ahead are no-shows
   60.5% of the time.
3. **Machine learning:** logistic regression wins five-fold cross-validation
   (about 0.77 ROC-AUC, ahead of the tuned random forest). Using a 0.35 decision
   threshold, the test set shows 0.571 recall with 49 of 198 appointments
   flagged and a test ROC-AUC of about 0.79.
4. **GenAI note classification:** 10 notes were processed with Gemini Flash
   (`gemini-flash-lite-latest`) using JSON schema and Pydantic validation in 14
   API calls. Blank note N004 was skipped without a call. Eight of the nine
   non-blank notes matched the reference root causes; one transient 503 was
   kept as an error row rather than repaired. Both notes classified as
   `forgot_or_no_reminder` had `reminder_sent = No`, and 5 of the 10 notes
   belong to appointments without a reminder.

## Model Selection

Models evaluated: logistic regression (with `StandardScaler` inside a pipeline),
depth-3 decision tree, random forest, and a tuned random forest
(`GridSearchCV` over `n_estimators` and `max_depth`). All comparison used
five-fold cross-validation on training data only — the test set was never used
to pick a model or threshold.

- Logistic regression: about 0.77 CV ROC-AUC (winner).
- Tuned random forest: about 0.77 CV ROC-AUC.
- Random forest: about 0.75 CV ROC-AUC.
- Depth-3 decision tree: about 0.68 CV ROC-AUC.

Final model: logistic regression. Selected threshold: 0.35 (chosen on
out-of-fold training predictions for the higher F1). Test recall: 0.571, with 49
appointments flagged out of 198; test ROC-AUC about 0.79.

Recall matters to CareLoop because each missed appointment is a wasted slot and
a lost chance to reach the patient. Flagging more at-risk appointments (higher
recall) lets the call centre intervene early, accepting some false positives.

## Business Recommendation

The appointments most likely to be missed are those booked far in advance
(31+ days: 60.5% no-show rate), at clinics with historically high no-show rates
such as Hadapsar Care Centre (27.3%), and for patients who did not receive a
reminder (reminder receipt is associated with lower no-show odds; the logistic
regression reminder coefficient is about -0.58). Among the 10 analysed notes,
both cases classed as `forgot_or_no_reminder` had `reminder_sent = No`, and 5 of
the 10 notes belong to appointments with no reminder — consistent with the
model's reminder association.

CareLoop should act first on: (1) sending and confirming reminders for all
appointments, since 438 of the 990 cleaned bookings had `reminder_sent = No`;
(2) targeting the 49 flagged test appointments (top risk scores in
`test_risk_scores.csv`) for proactive outreach the day before; (3)
prioritizing the 60.5% no-show band of 31+ day bookings for confirmation calls;
and (4) focusing on high-rate clinics such as Hadapsar Care Centre (27.3% across
143 appointments) and the small-sample Gomti Nagar Care Point (33.3% across 90
appointments).

## Limitations

Exactly three:

- Ten notes are illustrative, not representative of clinic-wide reasons; do not
  overgeneralize the GenAI root-cause distribution.
- Cleaning statistics (medians, fences) were calculated on the full cleaned set
  before the train/test split.
- The same patient may appear in both training and test data under the random
  split, so the reported test performance is mildly optimistic for true
  patient-level deployment.

## Repository Structure

```
careloop-clinics-no-show-guard/
├── data/
│   ├── appointments.csv
│   ├── clinics.csv
│   └── followup_notes.csv
├── 01_ingest_clean.ipynb
├── 02_queries.sql
├── 03_model.ipynb
├── 04_genai.ipynb
├── rejected_rows.json
├── appointments_clean.csv
├── clinics_enriched.csv
├── load_data.sql
├── test_risk_scores.csv
├── notes_analysed.csv
├── README.md
├── requirements.txt
└── .gitignore
```

## Reproduction Instructions

1. **Install requirements:** `pip install -r requirements.txt`. Notebook
   execution additionally needs `nbformat`, `nbclient`, and `ipykernel`.
2. **Run the Python notebooks:** execute `01_ingest_clean.ipynb`, then
   `03_model.ipynb`, then `04_genai.ipynb`. Notebook 01 regenerates
   `rejected_rows.json`, `appointments_clean.csv`, `clinics_enriched.csv`, and
   `load_data.sql`. Notebook 03 regenerates `test_risk_scores.csv`. Notebook 04
   regenerates `notes_analysed.csv`.
3. **Configure the Gemini API key:** notebook 04 prompts for the key at runtime
   via `input()`; it is never written to a file. The model is
   `gemini-flash-lite-latest`; if the thinking setting is rejected by a model,
   that one line is skipped while JSON mode, the schema and the Pydantic check
   remain unchanged. The key used in this build is not stored in the repository.
4. **Execute the SQL scripts:** run `02_queries.sql` against a MySQL 8
   server after loading `load_data.sql` (8 clinic `INSERT`s followed by
   990 appointment `INSERT`s). No local MySQL server is required to review the
   query logic.
5. **Reproduce the model:** re-run notebook 03; model selection uses training
   data only and the test set is scored exactly once.
6. **Generate output files:** the hand-off CSVs and `load_data.sql` are produced
   by the notebooks; do not edit them by hand.
7. **Publish:** create a public GitHub repository and upload every file listed
   under Submission (including the `data/` folder). Paste its URL at the top of
   this README. `gh` is not authenticated on the build machine, so repository
   creation and upload remain a manual step.

No API key or secret is included in this repository.
# care_loop
