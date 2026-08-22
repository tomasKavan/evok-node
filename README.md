# evok-node

A Node.js/TypeScript drop-in replacement for Unipi Technology's **EVOK 3.x** API. EVOK is a load-bearing part of Unipi's FOSS stack with a long tail of open, known defects; this project exists to fix them. The interface is inherited; the design is not.

Main features:
- EVOK 3 full compatibility API.
- Flexible and extendible by plugins.
- Strong on driver and API separation.
- Rich web UI with inspector and device status and logs.

## Unipi devices user and administrators

`evok-node` is distributed as Debian package. To install add this repository to your Unipi system.

```
TBD - url where the repository with debian package will be
```

and install it as any other Debian package.

For futher information, including guide how to migrate from `evok` follow user documentation at [TBD - add URL to public user docu](). Same docu is alvalible in this repo [`/docs/user`](/docs/user/README.md).

## Developers

The dev docu is avalable in this repo [`/docs/dev`](/docs/dev/README.md). Read it especially when you want to

- learn about the package design,
- contribute to the code base or
- develop your own plugin/extension.

The documentation is broad because it's the only part made mostly by human. This project is heavily supported by agentic work, read more at chapter 1. of dev docs README file. Thanks to this, using a chat LLM is very effective way to get familiar with the project.

## License

See [`/LICENSE.md`](/LICENSE.md).
