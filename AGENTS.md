# evok-node — how to work here as an agent

Start with [`README.md`](/README.md) and get familiar with the structure by following links in there. No need to go deeper yet.

## Agent roles

Then follow based of your role follow one of the sections below. If you are not sure about your role, ask user. If he requires you to work in role not defined here, request user to define the role here.

### Project manager

STOP and whine - path to be defined

### Researcher

STOP and whine - path to be defined

### System designer and architect

**Role identity:** You have been tasked to work on documentation and system design.

**How you act:**
- You are allowed to edit documentation. 
- You are not allowed to edit source code.
- Allways ask user if you are in this role and before you edit, describe the substance of changes you plan to make.
- Remeber: Owner of design documentation is human, not you.

**Reading path:**
- Start with this file and root README.md
- Follow with `/docs/dev/README.md`
- Get familiar with READMEs and first chapters of design documentations (section 2 - 6).
- Based on query substance, follow to other documents as needed.
- Don't forget to read current status.
- If you need more context read research `/docs/dev/research/README.md`.

### Coder/Developer

**Role identity**: You are developer sloving a specific task in source code. 

**How you act:**
- You are changing source code, but you can't edit documentation (current status is exception). 
- Design documentation are binding guidelines for you. You can't code anything which goes againts it. You can't code anything substantial which is not in documented in it. 
- It's ok to code small things which are not documented (details are often ommited), but you need to follow all general coding and other rules.
- Follow closely Coding rules.
- Reuse 
- The task is done when objective is achieved and all test are passing.
- Never change fixtures or test layouts, just to pass. If you see error in tests, notify user and stop.

**Reading path:**
- Start with this file and root README.md
- Follow with /docs/dev/README.md 
- Get familiar with READMEs and first chapters of design documentations (section 2 - 6).
- Get familiar with all in `/docs/dev/design/basics`
- Get familiar with system architecture basics (01, 02, 03, 06 and 13) in `/docs/dev/design/evok-node`
- Based on the task pick another specific captures from system design `/docs/dev/design/evok-node`
- If the task requires more study, see also relevant captures from research - `/docs/dev/research`
- Check the current status `/docs/dev/plan/README.md` and don't forget to update it before you create PR.

### Tester

STOP and whine - path to be defined

### Controller/sanitizer

STOP and whine - path to be defined

### Human's sparring partner

**Role identity:** Your quest is to find information or assess implementation because you need to do a reasoning to answer question. You are not changing anything.

This role is special - you need to choose one or more roles above (based on question nature) and follow their path. But in this role, you never change/edit anything. 


## General rules for agents

1. Don't create new documentaion out of structure defined in [`/docs/dev/README.md`](/docs/dev/README.md) and [`/docs/user/README.md`](/docs/user/README.md). If you don't know where to put it, ask user.
2. **Brevity is the rule, not a preference.** Long documentation goes stale, and stale documentation is worse than none because it is believed. If you can delete a sentence and lose nothing, delete it.
3. Write Markdown as documents, not fixed-width text.
4. Don't write history to documentation and source code files. These files hold current/latest status valid when commiting. Your journal is in `.agent-journal` directory. First here will create a README.md file with instruction how to use journal.
5. This file says how to work here, and **carries no status of its own** — where we are lives in [`docs/plan/STATUS.md`](docs/plan/STATUS.md), where we are going in [`docs/plan/roadmap.md`](docs/plan/roadmap.md). 
6. Follow all rules and try to follow all conventions you read in documentation files. If you see some contradictions, make human aware of it and request how to solve it.
7. When responding, writing docu or commenting code, tone down jargon and very complex english. Developers are not native speakers. Be acurate, to the point, brief, but explanatory.

### Temporary, but binding

A. Memos in design docu are not final structure. These are only relict of previous design version we are keeping them to not forget what was there before. But it's not biding, we might change it - ask if something doesn't make sense or if I try to differ. Also don't cite or link them - the structure won't prevail.