# kapsle

A Node.js/TypeScript platform that encapsulates functionality — hardware drivers, devices, services, rules — behind one common interface offered to clients.

Drivers expose endpoints; clients (WS API, Home API, UIs, Matter bridge) reach all of them the same way, with auth and ACL at the edge. Everything beyond the core comes as a plugin.

Main features:
- Small core: messaging, config, plugin host, WS API, basic drivers (Modbus, KV, system…).
- Plugins for everything else — installed from npm or uploaded, managed in the Inspector UI.
- Strong separation of drivers and APIs.
- Home automation devices and rules, exposed as a Matter bridge.
- Inspector UI, Home control UI and a mobile/desktop shell app.
- Multi-node sites: nodes link to each other, with a local or site-wide identity provider.

Hardware support comes as plugins — e.g. `@kapsle/plugin-unipi` for Unipi PLCs, a replacement for Unipi Technology's EVOK daemon.

## Unipi devices user and administrators

`kapsle` is distributed as Debian package. To install add this repository to your Unipi system.

```
TBD - url where the repository with debian package will be
```

and install it as any other Debian package.

For futher information, including how to replace `evok`, follow user documentation at [TBD - add URL to public user docu](). Same docu is alvalible in this repo [`/docs/user`](/docs/user/README.md).

## Developers

The dev docu is avalable in this repo [`/docs/dev`](/docs/dev/README.md). Read it especially when you want to

- learn about the package design,
- contribute to the code base or
- develop your own plugin/extension.

The documentation is broad because it's the only part made mostly by human. This project is heavily supported by agentic work, read more at chapter 1. of dev docs README file. Thanks to this, using a chat LLM is very effective way to get familiar with the project.

## License

See [`/LICENSE.md`](/LICENSE.md).
