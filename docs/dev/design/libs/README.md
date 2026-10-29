# Libraries

Protocol libraries that evok-node drivers use but that are not evok-node packages. Each one lives in its **own repository**, is published on its own, and is usable outside evok-node. Its design is written here, before its repository exists, so that the driver design (`design/evok-node`) and the library design are reviewed together.

A library holds a device's protocol: bytes, encodings, datapoints, a transport. A driver holds evok-node's side: config, endpoints, kinds, home templates. The rule for each pair: nothing in the library knows evok-node; nothing in the driver repeats the protocol.

| Doc | Library | Repository | Used by |
|---|---|---|---|
| [`01-wolf-ism8.md`](01-wolf-ism8.md) | `wolf-ism8` — Wolf ISM8i | `tomasKavan/wolf-ism8`, to be created before development starts | 12f (ISM8i driver) |

`mim-b19n` (`tomasKavan/mim-b19n`) predates this folder; its changes are listed in research/18 §8.2 and its use in 12g §9.
