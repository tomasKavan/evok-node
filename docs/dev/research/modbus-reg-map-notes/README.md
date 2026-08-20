# Register-map notes

One file per model, holding everything about a Unipi register map that is **ours** rather than Unipi's:
how a source was read, what a transcription had to infer, where the source contradicts itself, and what
a definition author must verify before trusting the extract.

The maps themselves live in [`docs/modbus-reg-map/`](../../modbus-reg-map/README.md), which holds ground
truth and mechanical extracts only. These notes were moved out of that tree on 2026-08-16 so that
nothing there is ours.

A note here is only worth writing when the source is not self-evident. Most models need none.

| Note | Says |
|---|---|
| [`accessory-iaq.md`](accessory-iaq.md) | The IAQ tables were read visually from a rendered PDF; which columns are inferred, and why the CSV schema deviates |
| [`extension-emo-r8.md`](extension-emo-r8.md) | The EMO-R8 source documents no register map at all — the jumper→unit-id table is the only usable content, and no CSV was invented |
