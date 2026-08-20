# Unipi register maps — ground truth

**Read-only. Nothing in this tree is ours.** These are Unipi's own published register maps, as
downloaded, plus mechanical extracts of them. They are the evidence every address table is generated
from and checked against, so they are worth exactly as much as their provenance.

## What belongs here

| | |
|---|---|
| **Sources as published** | `.pdf` and `.xlsx` exactly as downloaded from Unipi. Never edited, never re-saved, never "tidied" |
| **Mechanical extracts** | `.csv` transcribed from a source in this tree, one file per model × register space × section or group |

## What does not belong here

**Prose.** No analysis, no interpretation, no "what this implies for our definitions", and no notes on
what a transcription had to infer. That is research: it lives in
[`../research/modbus-reg-map-notes/`](../research/modbus-reg-map-notes/), one file per model, and it is
where the two notes that used to sit in this tree went (2026-08-16).

The distinction is the point. A reader must be able to trust that anything here is Unipi's claim and
not ours, without checking who wrote it.

## Extracts, and how much to trust them

A CSV is only as good as how it was read. Two cases, and they are not equally reliable:

- **From an `.xlsx`** — read from the sheet's own cells. Reliable, and re-derivable.
- **From a `.pdf`** — the maps are rendered images with no text layer, so they were read visually,
  page by page. **Verify against the PDF before generating anything from one.** Where a transcription
  had to infer a column the source does not state, the inference is recorded in the matching research
  note, not in the CSV.

Filenames follow the source's own vocabulary: `<Model>-<Space>-<section|group>-<N>.csv`, where the
source's word for the subdivision — *section* on Axon/Patron, *group* on Neuron and extensions — is
kept rather than normalised.

## Coverage

`1_1/` · `axon/` · `edge/` · `extensions/` · `neuron/` · `patron/` · `accessories/`

Axon is [a non-goal](../GOALS.md#non-goals); its CSVs stay as free cross-check data for the Neuron
register model, and for nothing else. Where a source documents no register map at all, there is no
CSV and none has been invented — see the EMO-R8 note.
