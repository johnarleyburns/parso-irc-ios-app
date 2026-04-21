# Agentic Coding in Practice: Lessons from Building a Production iOS IRC Client

### A Practitioner Report from Parso Consulting

**April 2026**

---

## Executive Summary

This whitepaper documents what Parso Consulting learned from using agentic coding tools — specifically OpenCode running Claude Sonnet via Amazon Bedrock — to build Parso IRC, a full-featured iOS IRC client, from initial commit to App Store submission in twelve days. We wrote zero lines of application code ourselves. The agent wrote all of it.

The headline finding is not that agentic coding works — it does — but that the conditions under which it works are specific, demanding, and frequently misunderstood.

**Model size is a hard floor.** Smaller open-source models, run locally, produced plausible-looking Swift code that did not function. Buttons had no backing logic. Protocol implementations were structurally correct but semantically wrong. We could not debug our way out of the inconsistencies they introduced. Claude Sonnet was the minimum model at which the project became tractable.

**"Vibe coding" is a misnomer at current capability levels.** We are experienced senior software engineers. We researched IRC protocol RFCs and IRCv3 extensions specifically to be able to prompt the agent correctly. Simply saying "build me an IRC app" produces nothing usable. Domain knowledge must come from somewhere, and today that somewhere is the human.

**One-shotting an app of any size is not feasible.** Every feature of consequence required a plan-build-test cycle: plan with the agent, implement with the agent, run CI, test on device, observe failures, return to the agent with precise descriptions of what broke and why. Compressing any step in that cycle produced regressions.

**UI bugs are a category of their own.** The agent cannot see the rendered interface. Every visual bug — an unreachable button, a stale data snapshot, messages appearing on the wrong side of the screen — required the human to observe it, articulate the symptom precisely, and guide the agent to the root cause in code. Budget at least twice the expected time for UI-heavy features.

**Substantial manual plumbing remains.** CI/CD automation, Apple developer account setup, code-signing certificates, provisioning profiles, App Store Connect configuration, and GitHub Actions secret management cannot be delegated to the agent. For iOS specifically, this plumbing consumed an estimated six to eight hours that were entirely outside the agentic workflow.

**The return on investment is real but requires honest scoping.** A senior engineer directing Claude Sonnet via OpenCode can produce a working, tested, CI/CD-deployed iOS application in twelve days that would otherwise take weeks. The efficiency gain is genuine. It does not eliminate the need for engineering judgment — it amplifies it.

---

## 1. Project Background: What Was Built

Parso IRC is a native iOS IRC client targeting Libera.Chat, OFTC, EFnet, and twenty-five other public IRC networks. It implements the core IRC protocol (RFC 1459) plus several IRCv3 extensions including CAP negotiation, SASL PLAIN authentication, server-time message tagging, and CHATHISTORY batch replay. The app provides a full channel and direct-message interface with persistent message history, unread badges, background reconnection, member lists, channel browsing, and a three-page onboarding flow.

The technology stack:

| Layer | Technology |
|---|---|
| Language | Swift 5.10 |
| UI framework | SwiftUI (iOS 17+) |
| Networking | Network.framework (`NWConnection`) |
| Concurrency | Swift `actor`, `async/await`, `CheckedContinuation`, Combine |
| Persistence | SQLite.swift with versioned schema migrations |
| Project generation | XcodeGen (declarative `project.yml`) |
| CI/CD | GitHub Actions → XcodeGen → Xcode build → iOS Simulator tests → TestFlight → App Store |
| Agentic tool | OpenCode CLI |
| Model | `bedrock-claude-sonnet-4-6` (Amazon Bedrock) |

The project ran from April 9 to April 21, 2026 — twelve calendar days. At completion:

- **213 commits** to `main`, each triggering a full CI build
- **55 Swift source files** across 12 feature and core modules
- **~14,400 lines** of production Swift code
- **~2,000 lines** of unit test code
- **175 unit tests** across 23 named test suites
- **31 SwiftUI view files** covering onboarding, server management, channel chat, direct messages, member lists, settings, and a debug terminal
- **0 lines** of application code written by a human

The app was submitted to the Apple App Store for review at the close of the project period.

---

## 2. The Agentic Coding Workflow

### 2.1 The Tool: OpenCode

OpenCode is a terminal-based agentic coding CLI. Unlike IDE-integrated assistants that suggest completions, OpenCode operates at the task level: it reads files, plans changes, writes code, runs shell commands, monitors CI output, and iterates — all in response to natural language prompts. It maintains a persistent conversation context across a session and uses a built-in task tracker (`TodoWrite`) to decompose complex requests into sub-tasks and track their completion.

The human interacts with OpenCode the way a senior engineer interacts with a junior one: describe the problem, describe the context, describe what you expect, and review the output. The difference is that the "junior engineer" has read more Swift code than any human alive and never gets tired.

### 2.2 The Plan/Build/Test Cycle

We never attempted to one-shot a feature. Every significant piece of work followed this cycle:

1. **Plan**: Ask the agent to read the relevant files and propose a complete plan before writing any code. The agent would produce a detailed breakdown of every file to change, every bug's root cause, and every trade-off in the proposed fix. We would review this plan, ask clarifying questions, and sometimes redirect before any code was written.

2. **Build**: Ask the agent to implement the plan. It would read each file, make surgical edits, run the unit test suite locally (`swift run`), and report results.

3. **Push and CI**: Every commit triggered the full GitHub Actions pipeline: XcodeGen project generation, SPM dependency resolution, iOS Simulator boot, Xcode unit test run, and TestFlight archive. The agent would monitor CI output and fix compilation errors.

4. **Device test**: A human would install the build on an iPhone and test the actual behavior. Observed failures were described back to the agent in plain language.

5. **Iterate**: Return to step 1 for the next feature or bug.

This cycle was not optional. Skipping device testing meant UI bugs persisted. Skipping the planning phase meant the implementation was often correct in isolation but wrong at the integration point. The cycle is the method.

### 2.3 Prompting: What "Precise Technical Specification" Actually Means

The single most important determinant of output quality was prompt precision. The gap between an ineffective prompt and an effective one is not subtlety — it is an order of magnitude of specificity.

**Ineffective prompt:**
> "Add chat history support so I can see previous messages when I join a channel."

This produced an implementation that sent `CHATHISTORY` at the wrong point in the connection handshake, routed history messages to the wrong callback, and failed silently on most servers.

**Effective prompt (after human IRC research):**
> "The `CHATHISTORY` command must only be sent after the server sends `366 RPL_ENDOFNAMES` for the channel. This is the definitive confirmation that the `JOIN` has been fully processed server-side. Sending `CHATHISTORY` before `366` arrives causes Libera.Chat to silently ignore it because you haven't been confirmed as joined yet. Add an `onEndOfNames` callback to `IRCClient` that fires when `366` arrives for a specific channel, and trigger `requestChatHistoryIfSupported()` from that callback in `ChannelViewModel` instead of from `start()`."

The difference is that the second prompt embeds protocol knowledge — the exact numeric reply, the exact server behavior, the exact sequencing constraint — that the agent does not and cannot infer from the phrase "chat history support." That knowledge had to come from a human reading the IRCv3 CHATHISTORY draft specification.

This pattern repeated throughout the project. The agent is a highly skilled implementer. It is not a domain expert in IRC, Apple code-signing, Swift actor isolation semantics, or any other specific technical domain. Those things must be understood by the human and translated into prompts.

### 2.4 The Role of Automated Testing

The 175-unit test suite was not a nice-to-have. It was the mechanism by which regressions were caught before they reached the device. The test suite ran on every commit in approximately ten minutes. This created a tight feedback loop that made the plan/build/test cycle viable at the pace we maintained.

The tests were written by the agent, not by us. We directed the agent to write tests for every protocol invariant, every routing rule, and every bug fix, using a regression-first discipline: the test for the bug was written before or alongside the fix, so that re-introducing the bug in a future refactor would immediately fail CI.

The test file grew from zero to 2,026 lines across 175 tests covering:
- IRC message parser correctness (eleven edge cases)
- CAP negotiation state machine (false-positive `chathistoryEnabled`, multi-line LS handling)
- SASL PLAIN credential encoding (base64 structure, special characters, empty passwords)
- CHATHISTORY flow (trigger sequencing, limit capping, batch type routing)
- The `PASS` suppression regression (the root cause of the most persistent send failure)
- Member list parsing, deduplication, sort order, and channel filter isolation
- Combine fan-out message routing (background channel persistence, unread counting)
- DM vs. channel message routing (PRIVMSG to nick must not appear in channel views)
- IRC event routing (join/quit/nick events isolated to correct channels and views)

---

## 3. What Worked Well

### 3.1 Architecture at Scale

The agent's most impressive capability was proposing and implementing correct software architecture for a non-trivial concurrent system. When faced with a broken single-slot callback design that dropped messages for non-active channels, the agent correctly diagnosed the architectural failure and proposed a Combine-based fan-out redesign:

- `IRCClientManager` registers permanent `IRCClient` callbacks once on connect
- Each server connection has a `PassthroughSubject<IRCMessage, Never>` and `PassthroughSubject<IRCEvent, Never>`
- `ChannelViewModel` subscribes via Combine rather than overwriting `client.onMessage`
- `stop()` reduces to `cancellables.removeAll()` — no more null-setting of shared callbacks

This is not a trivial architectural decision. It requires understanding Swift's structured concurrency, Combine publisher lifetimes, and the ownership model of SwiftUI's `@StateObject`. The agent got all of these right on the first attempt once the problem was correctly framed.

### 3.2 Concurrency Bug Diagnosis

The most technically demanding fix in the project involved a Swift actor deadlock that caused the IRC registration handshake to time out, leaving every send attempt failing silently with `IRCError.notConnected`.

The root cause: `IRCClient` is a Swift `actor`. The connection flow called `waitForCapNegotiation()`, which spun a `while !isCapNegotiationComplete { await Task.sleep }` loop inside the actor. This loop held the actor's execution context. `handleMessage()` — which needed to run to set `isCapNegotiationComplete = true` — is also actor-isolated. The two tasks were serialized: the polling loop ran forever; `handleMessage()` could never run; the flag was never set; the 10-second timeout eventually fired; `NICK`/`USER` were sent too late; Libera.Chat had already closed the connection.

The fix required replacing the polling loops with `CheckedContinuation`-based suspension: the connect flow suspends without holding the actor, allowing incoming message processing to proceed. The agent correctly implemented this using actor-isolated timeout helper methods (`timeoutCapNegotiation()`, `timeoutCapAck()`) rather than setting actor properties from background `Task` closures — a subtle but critical distinction that the Swift concurrency compiler enforces at build time.

We presented the agent with a description of the symptoms and the architectural model. It produced the correct diagnosis and implementation. No concurrency expert human time was spent writing the actual fix.

### 3.3 Database Schema Management

The agent maintained a clean migration discipline throughout the project. Every new column (`unread_count`, `use_connection_password`, `is_dm`) was added via a `PRAGMA table_info()` guard that checked for the column's existence before issuing `ALTER TABLE`. This prevented both silent data loss on upgrade and crashes on a fresh install. The schema reached six migration phases without incident.

### 3.4 CI/CD Pipeline Construction

The agent wrote the entire 200-line GitHub Actions workflow, including:
- Dynamic iOS Simulator UDID detection using a Python script (to avoid hardcoded device names that break when Apple renames devices)
- XcodeGen caching keyed on version hash
- SPM dependency caching keyed on `Package.resolved`
- A two-job pipeline where the TestFlight archive only runs if unit tests pass
- Graceful cleanup of build keychains and API keys in `always:` blocks

The human's contribution was providing the seven secret names and values (certificates, provisioning profiles, App Store Connect API key). The agent handled all structural workflow decisions.

### 3.5 Regression Test Coverage for Every Bug

For every significant bug fixed, the agent wrote a corresponding regression test that:
- Named the test after the specific failure mode (e.g., `testOwnEchoSuppressed`, `testErrorBadPasswordKillsConnection`, `testSuppressingPASSPreventsErrorBadPassword`)
- Described the bug in a code comment above the assertion
- Verified both the old (broken) behavior and the new (correct) behavior in the same test

This practice transformed the test suite from a correctness check into a living history of the project's bugs and their fixes.

---

## 4. What Failed or Required Heavy Human Intervention

### 4.1 The Persistent `PASS` Bug: Protocol Knowledge the Agent Doesn't Have

The single most damaging recurring bug in the project — messages appearing locally but never reaching the IRC server — had the same root cause across three separate incarnations: the agent kept sending the IRC `PASS` command to Libera.Chat.

IRC's `PASS` command is used to authenticate to private servers and bouncers that require a server-level password. Libera.Chat is a public network that does not use server-level passwords. When it receives an unexpected `PASS`, it responds with `ERROR :Bad password` and immediately closes the TCP connection. The app then showed a connected state (because `001 RPL_WELCOME` had already arrived in one code path) while silently failing on every send attempt.

The agent introduced this bug in three different ways across three separate sessions:
1. By setting `serverPassword: server.password` in `IRCClientManager.connect()`, passing the NickServ/SASL credential as a server connection password
2. By setting `saslEnabled: true` by default during onboarding for unregistered nicks (SASL only works for nicks registered with NickServ; an unregistered nick attempting SASL causes the server to abort)
3. After fixing #1, by not accounting for the case where `useConnectionPassword = false` was the new default but old server records in the database had the old behavior

The fix that held was adding a `useConnectionPassword: Bool` field to the `Server` model (defaulting to `false`) and passing `serverPassword: server.useConnectionPassword ? server.password : nil` to `IRCClient.connect()`. The agent did not propose this design. We proposed it after researching how IRC server passwords differ from NickServ credentials.

**The lesson**: The agent has no knowledge of which public IRC networks use server-level passwords and which do not. No amount of prompting "make sure authentication works" surfaces this — because the agent does not know what "authentication" means in the context of Libera.Chat's specific policy. Domain knowledge must come from outside the model.

### 4.2 UI Bugs the Agent Cannot See

UI bugs were the most consistent category of failure throughout the project, and the hardest to resolve. Three examples illustrate the pattern.

**The stale member list**: `MemberListView` received `let members: [ChannelMember]` — a value copy made when the sheet opened. If the `NAMES` reply hadn't arrived yet (common on first join), the sheet showed an empty list. The agent had written this code correctly from its own perspective: it passed the current value of `viewModel.members` to the sheet. The bug was that SwiftUI value semantics meant the sheet never saw updates. The fix was to pass `@ObservedObject var viewModel: ChannelViewModel` so the sheet observed the live member list. This required a human to notice that the member list was sometimes blank, test it on device, and describe the observation before the agent could propose the correct fix.

**Messages not right-aligned after navigation**: When a user returns to a channel they previously visited, their own messages appeared left-aligned (incoming style) instead of right-aligned in a blue bubble. The agent had correctly set `isFromCurrentUser: true` on outgoing messages and correctly used it in the message renderer. The bug was that `isFromCurrentUser` was not stored in the SQLite database schema. When messages were loaded from the database on re-entry, the field defaulted to `false` for all messages. The agent could not discover this by reading the code — the `Message` struct had `var isFromCurrentUser: Bool`, the renderer used it correctly, and the database persistence code looked reasonable. The missing connection was that `saveMessage()` simply never included the field in its `INSERT` statement and `fetchMessages()` never read it back. This required a human to notice the visual regression, describe it precisely ("my messages appear on the wrong side after I navigate away and come back"), and allow the agent to audit the full persistence path.

**The DM navigation dead-end**: Tapping "Send Direct Message" from the member list navigated the user back to the channel instead of opening a DM conversation. The agent had implemented the `onDM` callback, but it called `ConversationsViewModel(ircManager: ircManager).openDM(with: nick, serverId: sid)` — creating a throwaway `ConversationsViewModel` instance that saved the DM to the database and immediately deallocated. The `appState.selectedChannelId = dm.id` line updated state, but because the `ConversationsViewModel` was a local constant (not a `@StateObject`), the DM channel was not persisted to the DB, the sidebar didn't update, and the navigation destination didn't exist. Diagnosing this required the human to observe the symptom ("it just takes me back to the channel"), describe it, and allow the agent three separate diagnosis passes before the correct three-part fix emerged: use `ircManager.openOrCreateDM()` instead of a throwaway ViewModel, inject a `navigateToDM` environment key from `RootView`, and push `NavDestination.dm(...)` onto the navigation path.

In every case, the bug was invisible to a code reader and required visual observation on a running device.

### 4.3 The Single-Slot Callback Architecture: The Agent Broke Its Own System

Early in the project, the agent designed `ChannelViewModel.registerCallbacks()` to assign closures directly to `IRCClient` properties: `client.onMessage = { ... }`, `client.onJoin = { ... }`, and so on. Each property held exactly one closure.

This design worked for a single active channel. When the user navigated to a second channel, the new `ChannelViewModel` called `registerCallbacks()` and overwrote all the closures. When they navigated back to the first channel, the first ViewModel's `stop()` had already set all closures to `nil`. The second channel's closures were now gone too. Every message for every channel was silently dropped.

The agent introduced this design, did not notice the architectural flaw, and attempted to patch it in two subsequent sessions before we framed the problem clearly enough for a root-cause fix. The correct fix — a Combine fan-out where `IRCClientManager` owns permanent callbacks and `ChannelViewModel` subscribes — required a complete rewrite of both `IRCClientManager` and `ChannelViewModel` (approximately 1,500 lines across two files).

This illustrates a failure mode that is specific to agentic coding: the agent does not maintain a global mental model of the system it has built. It reads the files it is asked to read and reasons about what it sees. It does not spontaneously notice that a design decision made in Phase 2 will create a correctness failure in Phase 6. The human must connect those dots.

### 4.4 Compounding Fixes and Introduced Regressions

A partial list of regressions introduced during fixes:

- The `dmChannelIds` published property was accidentally omitted when `channelMembershipVersion` was added nearby in the same edit, causing a compilation error on CI
- The SASL credential submission method (`authenticateSASL()`) existed in the codebase but was never called during the connect flow; it was added in one session and silently orphaned in a subsequent architectural refactor
- `isCapNegotiationComplete` was originally set by a blind 500ms `Task.sleep`, replaced with a polling loop (which caused the actor deadlock described above), replaced with a `CheckedContinuation` (which had incorrect actor isolation), replaced with actor-isolated timeout helper methods — four implementations of one feature
- The `onEndOfNames` callback was added to `IRCClient` for the CHATHISTORY fix, but a subsequent refactor to the Combine fan-out architecture moved all callbacks to `IRCClientManager`, leaving `onEndOfNames` wired in `ChannelViewModel` directly via the client — which then got overwritten by the next channel's registration

Each regression was caught by CI or device testing within one to two commits. The automated test suite was the mechanism that made this tolerable.

### 4.5 The O(N²) Crash the Agent Created, Didn't Catch, and Couldn't Find Itself

The most instructive failure in the entire project was a performance bug that caused the app to freeze for ten seconds and then be killed by the iOS watchdog process — silently, with no crash report — every time the user opened a channel with chat history. The agent introduced it, the agent's unit tests did not catch it, and a human tester had to find it.

**What the agent built:** `ChannelViewModel.rebuildDisplay()` was called after every single message append — including during CHATHISTORY batch replay. `rebuildDisplay()` iterates all accumulated messages. For a batch of N history messages, this produced N calls to an O(N) function: 1+2+3+...+N = O(N²) total work. Simultaneously, `MessageRowView.isMention` compiled a fresh `NSRegularExpression` on every render of every message row. With SwiftUI re-rendering all rows on every `displayMessages` change, this produced hundreds of regex compilations in the same tight loop.

The combined effect saturated the main thread. iOS terminated the app after approximately ten seconds. Because this was a watchdog kill rather than a code crash, it produced no symbolicated crash report — only a "App Quit Unexpectedly" dialog. The user reported: "it freezes up for a long time, and finally has a crash report window, but I never receive the crash report." This is the characteristic fingerprint of a watchdog termination.

**Why the agent's tests missed it:** The agent wrote 191 unit tests covering functional correctness of every component. Those tests verified that `rebuildDisplay()` produced correct output given correct input. No test asked how many times `rebuildDisplay()` would be called when 100 history messages arrived via Combine. No test asked whether `isMention` compiled a new regex on every invocation or reused a cached one. The agent assembled individually-correct components in a way that was collectively catastrophic under realistic load — and its test suite, which it also wrote, was not designed to catch this class of failure.

**Why the fixes required three CI cycles:** Once the human identified the symptom, the agent correctly diagnosed all three root causes and proposed correct fixes. The fixes themselves — batching `rebuildDisplay()`, caching the regex in `NSCache`, converting `rulesURL` to a `@Published var` — are all sound. But implementing them introduced two new compilation failures that only appeared on the CI's macOS/Xcode 16.4 environment, not on the Linux `swift run` test harness used locally:

1. `@Published private(set)` with `didSet` is not supported by Xcode 16.4's Swift compiler in the way the agent expected. This required one CI cycle to discover and one to fix incompletely.
2. In fixing the `@Published private(set)` issue, an edit to `ChannelViewModel.swift` silently deleted five `@Published` property declarations — `members`, `currentNick`, `isLoadingHistory`, `unreadCount`, and `failedMessageIds`. These are the core observable properties the entire ViewModel is built around. They were deleted because the agent's edit used an anchor pattern that spanned the section containing them, and the replacement text did not include them. The agent did not verify that the edit preserved all content between the anchor points.

The deleted properties caused 17 compilation errors across 3 view files. The local `swift run` test suite passed because the standalone Swift package does not compile SwiftUI views. CI failed. A human had to prompt "check the build." The agent diagnosed the errors, restored the properties, and pushed again. Green.

Total time from first performance fix push to final green build: approximately 1.5 hours across four CI runs, each requiring a human to prompt the next step.

**The compound lesson:** The agent introduced an O(N²) bug. Its own tests did not catch it. A human found it at runtime. The agent's fix introduced a silent code deletion. Its own tests did not catch that either. A different human prompt found it. The test suite that was supposed to be the safety net had two structural gaps: it did not test performance characteristics of integrated paths, and it did not run on the same compiler toolchain as the production build.

### 4.6 Smaller Open-Source Models Are Not Viable for This Scale

Prior to the OpenCode/Claude Sonnet approach, the team experimented with locally-run open-source models. The experience was instructive in establishing what the minimum viable capability level is.

Smaller models produced code that:
- Compiled but did not function (UI elements with no backing logic, buttons that called methods that didn't exist, navigation that went nowhere)
- Implemented protocol structures that looked correct but had subtle semantic errors that were not surfaced until runtime (for example, sending `AUTHENTICATE` to a server that hadn't ACKed `sasl` in CAP)
- Could not maintain consistency across files in a multi-file edit — a type changed in one file would not propagate correctly to its usages in three other files
- Failed to diagnose their own compilation errors in subsequent turns, producing cascading error sets

Most critically, smaller models introduced UI bugs at a rate that exceeded our ability to fix them. Each fix introduced a new set of visual regressions that could not be observed without running the app, creating a spiraling backlog.

Claude Sonnet was the inflection point. The difference was not marginal — it was categorical. The same prompts that produced broken, inconsistent code from smaller models produced correct, compilable, functionally sound code from Sonnet. This was the most important infrastructure decision of the project.

### 4.6 Manual Plumbing: The Gap No Agent Currently Fills

A complete accounting of manual steps required that were outside the agentic workflow:

**Apple Developer Program:**
- Developer Program enrollment ($99/year, requires Apple ID, payment, identity verification — 24-48 hour approval turnaround)
- App ID creation with specific bundle identifier (`guru.parso.ios-irc-app`) and capability entitlements
- App Store Connect app record creation, privacy policy URL, age rating questionnaire, export compliance declaration

**Code Signing:**
- Distribution certificate generation via Xcode Organizer (requires physical Mac, Keychain access, Apple ID authentication)
- Certificate export to `.p12` with password
- Provisioning profile creation (tied to App ID, certificate, and device UDIDs)
- Profile download and base64 encoding for CI secret storage

**GitHub Actions Secrets (7 required):**
- `APPLE_CERTIFICATE_BASE64` — the distribution certificate
- `APPLE_CERTIFICATE_PASSWORD` — certificate export password
- `KEYCHAIN_PASSWORD` — temporary keychain password for CI
- `PROVISIONING_PROFILE_BASE64` — the provisioning profile
- `TEAM_ID` — the Apple Developer Team ID
- `APPSTORE_API_KEY_ID` — App Store Connect API key identifier
- `APPSTORE_API_ISSUER_ID` — App Store Connect issuer ID
- `APPSTORE_API_PRIVATE_KEY` — the private key `.p8` file content

**On-Device Testing:**
- Physical iPhone, developer mode enabled
- TestFlight installation and internal tester management
- Observation and description of runtime behavior

Total estimated time for this plumbing: six to eight hours for an experienced iOS developer. For someone new to the Apple ecosystem, two to three days is realistic.

The agent wrote the CI workflow that consumes all of these secrets. It cannot generate the secrets themselves. This boundary is sharp and currently fixed.

---

## 5. Quantitative Summary

| Metric | Value |
|---|---|
| Total calendar days | 12 (April 9–21, 2026) |
| Total commits | 220+ |
| Production lines of code | ~14,400 |
| Source files | 55 Swift files |
| Unit tests | 191 across 25 suites |
| UI view files | 31 |
| CI builds triggered | ~220 (one per commit) |
| CI builds failing (compilation errors) | ~18 (~8%) |
| Major architectural rework cycles | 3 |
| Bugs requiring 3+ fix attempts | 6+ |
| Performance bugs causing watchdog crash | 1 (O(N²) + per-render regex) |
| CI failures caused by agent's own fix introducing new bugs | 3 (for one performance fix) |
| Agent-introduced silent code deletions caught only by CI | 1 (5 @Published properties dropped) |
| Human application code written | 0 lines |
| Human protocol research (estimated) | ~8 hours |
| Apple dev account / CI plumbing (estimated) | ~7 hours |
| Agent model | Claude Sonnet (`bedrock-claude-sonnet-4-6`) |

---

## 6. Lessons Learned

### L1: Model size is a hard floor, not a dial

There is a threshold below which agentic coding on a multi-file application does not produce working software. It produces working-looking software. The difference is invisible until you run it.

Claude Sonnet was the first model in our experience that crossed this threshold for iOS development. We do not believe this is about the quantity of Swift training data — it is about reasoning capability: the ability to hold a mental model of a concurrent system, identify the interaction between a design in one file and a bug in another, and propose a fix that is correct at the architectural level rather than syntactically plausible.

Teams evaluating agentic coding tools should test with real, multi-file projects of representative complexity — not toy examples — before drawing conclusions about capability.

### L2: "Vibe coding" is a misnomer at current capability levels

The popular conception of agentic coding as "describe what you want and receive a working app" does not match the current state of the technology. The correct mental model is: you are the domain expert and architect; the agent is the implementer with encyclopedic knowledge of the language and framework.

We needed to understand IRC's CAP negotiation protocol to prompt the agent to implement it correctly. We needed to understand Swift actor isolation to diagnose the deadlock. We needed to understand Apple's code-signing model to set up CI. None of this knowledge came from the agent. Our value-add as engineers was translating domain knowledge into precise implementation specifications.

This is not a criticism of current models. It is a description of the current division of labor that teams should understand before committing to an agentic coding approach.

### L3: The plan/build/test cycle is the method, not the overhead

When we skipped the planning phase and went directly to implementation, the agent often produced code that was locally correct but architecturally wrong. When we skipped device testing and relied only on CI passing, UI bugs accumulated silently. When we attempted to implement multiple features in a single session without an intermediate test cycle, regressions compounded faster than we could track them.

The plan/build/test cycle felt like overhead in the moment. In retrospect, it was the mechanism that made twelve-day completion possible. The sessions where we followed it precisely were the sessions with clean commits and no regressions. The sessions where we cut corners were the sessions that produced the six-plus bugs requiring multiple fix attempts.

### L4: UI bugs require a human in the loop

The agent produces correct UI code relative to the specification it is given. It cannot observe a running application. Every bug that manifests as a visual or interactive failure on a real device — a stale data snapshot, a button that routes nowhere, a message on the wrong side of the screen — requires the human to observe it, describe it precisely, and maintain that description accurately enough for the agent to locate the root cause.

This is a fundamental limitation of text-in/text-out models applied to visual software. It is not model-specific. It will require either automated visual testing infrastructure or a fundamentally different model capability to resolve. For now, budget a human tester in every agentic iOS development cycle.

### L5: The agent will occasionally break what it just fixed

Architectural refactors are the highest-risk operation. When the agent rewrites a large component — as it did three times in this project — there is a non-trivial probability that a related component is left inconsistent. The inconsistency may not surface until a later feature or a different code path exercises it.

The mitigation is a comprehensive automated test suite that covers not just the happy path but the integration points between components. When the agent dropped `dmChannelIds` from a refactored file, CI caught it in the next build. Without that test coverage, the omission would have reached a device and presented as an unexplained runtime failure.

### L6: Incremental complexity is safer than ambitious scope

The most stable phases of the project were those where a single, well-defined feature was added to a working codebase. The least stable were those where we brought a list of ten issues and asked for all of them to be addressed in one session.

The agent can handle broad scope. It cannot simultaneously maintain correctness across ten interdependent changes. Smaller increments with CI validation between them produced a cleaner commit history and fewer compounding regressions than ambitious multi-feature sessions.

### L7: Plumbing is outside the current scope of agentic coding

The gap between "the agent wrote all the code" and "the app is on the App Store" is filled entirely by manual work. Developer accounts, certificates, provisioning profiles, secret management, and on-device testing cannot be delegated today. This gap is not shrinking as fast as the code generation capabilities are improving.

Project timelines should account for this plumbing as a separate category from agentic coding time. They should not be conflated.

### L8: Unit tests matter more for agentic coding than for any other development approach — and the agent won't write the right ones without direction

The most dangerous failure mode we encountered was not a bug the agent wrote — it was a class of bugs the agent's tests were structurally incapable of catching.

The agent produced 191 unit tests. Every one of them asserted functional correctness: given this input, produce this output. Not one of them asked: how many times is this function called under realistic load? How many objects are allocated per render? What happens to computational complexity when N is 100 instead of 1?

The O(N²) watchdog crash was not caught by any of those 191 tests because none of them modeled the integrated rendering pipeline under load. The agent wrote tests for the pieces it could reason about discretely. It did not spontaneously reason about the emergent behavior of those pieces combined — `append()` calling `rebuildDisplay()` calling SwiftUI's `@Published` observer triggering a layout pass, 100 times in sequence, while `isMention` compiled a fresh regex per row per pass.

This is not a limitation unique to Claude Sonnet. It is a structural property of how current models approach test generation: they write tests for the behaviors they were instructed to implement, covering the code paths they understand as important. They do not write tests for the performance failure modes they didn't predict.

**The implication for teams adopting agentic coding:** Unit tests written entirely by the agent are necessary but not sufficient. A human must direct the agent to write tests for the properties the agent won't think to test:

- **Performance path tests**: for any function that is called in a loop (especially a Combine subscriber processing a batch), assert an upper bound on the number of calls. `testRebuildCalledOncePerBatch()` would have caught the O(N²) bug before any human ran the app.
- **Render-phase invariants**: for computed properties on View structs, assert that they do not perform expensive operations (regex compilation, object allocation, database calls). These execute on every layout pass.
- **Integration tests under load**: for any feature involving batched data (history replay, bulk DB loads, multi-message events), test with N=100, not N=1.
- **Post-edit completeness checks**: after any large edit to a file, a test that simply exercises every public method of the affected class will immediately surface "cannot find X in scope" errors from silent property deletions — before CI, not after.

The second agent-introduced failure in the same fix cycle — five critical `@Published` property declarations silently deleted from `ChannelViewModel.swift` — is a different but equally important category: **the agent's editing process can silently remove code it didn't intend to remove, and its own test suite won't catch it if the deleted code isn't exercised by the test runner.**

When the agent uses a find-and-replace edit, it identifies a section of a file by an `oldString` anchor and replaces it with `newString`. If the `oldString` spans a region that contains code beyond what the agent intends to change, and that code is absent from `newString`, it is silently deleted. The agent does not diff its edit against the original to verify that only the intended changes were made. It does not check that every symbol referenced elsewhere in the file still exists after the edit.

In this case: five `@Published` properties — `members`, `currentNick`, `isLoadingHistory`, `unreadCount`, `failedMessageIds` — were deleted. These properties are referenced in dozens of places throughout the same file and in three other view files. The local test suite (a Linux `swift run` package) passed because it doesn't compile SwiftUI views. The Xcode build on CI failed with 17 "cannot find X in scope" errors. The human had to prompt "check the build."

**The defense against silent code deletion is a test suite that is comprehensive enough to exercise the deleted code.** If there had been a test that called `viewModel.send()`, `viewModel.members`, `viewModel.currentNick`, and `viewModel.isLoadingHistory` — even trivially — the Linux test runner would have failed immediately on those symbols being missing. The five deleted properties were never directly tested as symbols; they were only tested indirectly through higher-level behavior. That gap allowed the deletion to go undetected locally.

**The practical rule:** for every `@Published` property, every public method, and every computed property on any `ObservableObject`, there should be at least one test that references it by name. Not necessarily a deep test — just one that will fail to compile if the declaration is removed. Think of these as "symbol existence tests." They are trivial to write and provide essential protection against the agent's most common editing failure mode.

### L9: The agent's test environment and the production build environment are not the same — this gap will cost you CI cycles

Throughout this project, unit tests ran via `swift run` on a Linux toolchain. This was fast (under two minutes) and provided a useful functional correctness signal. It did not tell us whether the code would compile on Xcode 16.4 on macOS with SwiftUI's specific type checker.

This gap produced at least three avoidable CI failures:

1. `@Published private(set)` combined with `didSet` is rejected by Xcode 16.4's Swift compiler in contexts involving `@ObservedObject` key-path lookup. This works on Linux. It fails on macOS. The agent had no way to know this without running a macOS build.

2. `@Published private(set)` on its own (without `didSet`) also broke `@ObservedObject` dynamic member subscript in Xcode 16.4 — a compiler-version-specific behavior. Again: passes Linux, fails macOS.

3. The silent property deletion described in L8 was caught by CI, not by local tests, specifically because the CI ran on macOS with Xcode and attempted to compile the full SwiftUI view hierarchy.

The pattern across all three: the agent's local test runner was the wrong environment for catching the errors the agent was making. The tests passed locally. The build failed remotely. A human had to observe the failure, prompt the agent, and wait for another CI cycle.

**The structural fix:** any project using agentic coding should run at minimum a compilation check in the production build environment on every commit — not just a language-level test runner. For iOS, this means running `xcodebuild build` (or at minimum `xcodebuild analyze`) in the CI pipeline before the full test suite. Compilation failures surface in minutes; a full archive takes fifteen. The faster the feedback loop between "agent edits code" and "code is verified against the real compiler," the fewer wasted CI cycles.

More broadly: be explicit with the agent about what the local test runner can and cannot verify. If the agent believes that `swift run` passing means the build is clean, it will commit platform-specific failures with confidence. It should instead be directed to treat any edit that touches Swift type annotations, property wrappers, or SwiftUI view protocols as "must be verified by CI before considering done."

### L10: How a working app eventually emerged from this process

It is worth being explicit about how the app reached a working state, because the path was not linear and the agent did not get there alone.

The app works. It connects to Libera.Chat, sends and receives messages in real time, loads chat history, shows unread badges, supports direct messages, reconnects automatically, and has been submitted to the App Store. This is a genuine result. It is also the result of a specific kind of human-agent collaboration that is worth documenting precisely.

**What the agent contributed:**
- All application code — 14,400 lines across 55 Swift files, zero lines written by a human
- Correct diagnosis of most bugs once the symptom was described with sufficient precision
- Architectural designs that were sound at the component level (the Combine fan-out, the `CheckedContinuation`-based CAP handshake, the SQLite migration system)
- 191 unit tests covering functional correctness of protocol parsing, message routing, SASL encoding, member list management, and routing logic
- The CI/CD pipeline including dynamic simulator detection, SPM caching, and TestFlight upload
- All of the above without any human writing a single line of application code

**What the human contributed:**
- IRC protocol research (RFC 1459, IRCv3 CAP, CHATHISTORY draft spec) translated into precise implementation prompts
- On-device testing — every runtime failure was discovered by a human running the app on a phone
- Observation and articulation of symptoms the agent could not see (the freeze-and-crash, the wrong message alignment, the DM appearing in a channel)
- Persistence through the agent's own self-inflicted regressions — three prompts of "check the build now" across one bug fix
- Apple developer account, certificate, provisioning profile, and GitHub Actions secret setup
- The judgment to push back when the agent's explanation seemed incomplete and ask it to think harder

**What neither the agent nor the human could have done alone:**
- The human alone could not have written 14,400 lines of Swift in twelve days
- The agent alone would have never run the app on a phone and noticed the freeze
- The agent alone would have written tests that passed but missed the O(N²) path
- The human alone would not have diagnosed the actor deadlock or the `PASS` command killing the Libera.Chat connection

The working app is the product of genuine collaboration: the agent as an extremely fast, extremely knowledgeable implementer with significant blind spots; the human as the domain expert, quality assurance function, and error-recovery supervisor. Neither role is optional at the current state of the technology.

---

## 7. Recommendations

### For startups building consumer apps

Claude Sonnet–class agentic coding is a genuine force multiplier for a one or two-person engineering team. A senior iOS engineer directing the agent can build a working, tested, CI/CD-deployed application in one to two weeks that would otherwise take six to eight weeks. This is a real efficiency gain, not marketing.

The caveats: the engineer must understand the domain well enough to write precise prompts, must maintain an active plan/build/test cycle, and must allocate separate time for Apple ecosystem plumbing. "Hire a junior developer and give them an AI assistant" is not the right model. "Give a senior engineer a faster implementation path" is.

### For enterprise consulting shops

Agentic coding is viable for greenfield internal tooling with well-specified requirements. It is less well-suited to complex legacy systems where the agent would need to maintain a mental model of many years of accumulated design decisions.

The staffing implication: agentic coding does not reduce the need for senior engineers. It increases the leverage of senior engineers and reduces the routine implementation work that would otherwise fall to mid-level developers. Teams should expect to retrain engineers on prompt engineering and agentic workflow management as distinct skills, not assume that existing engineering practices transfer directly.

Do not promise clients "hours not weeks." Twelve days for a simple consumer app, with an experienced team, is an honest data point. Set expectations accordingly.

### For AI tooling and platform teams

The two largest unmet needs in the current agentic coding stack are:

1. **Automated UI verification.** The agent's biggest blind spot is the rendered interface. Any tooling that closes the loop between "agent writes SwiftUI code" and "agent observes the rendered result" — whether through accessibility tree inspection, screenshot diffing, or simulator interaction — would have a material impact on the UI bug rate.

2. **Plumbing automation.** Apple's code-signing and provisioning infrastructure, GitHub Actions secret management, and App Store Connect configuration are the manual boundary conditions for every iOS project. Tooling that automates certificate lifecycle, provisioning profile rotation, and secret injection would eliminate the most friction-heavy category of non-agentic work.

---

## 8. Accessibility

### 8.1 Accessibility Audit and What We Found

After the app was functionally complete and submitted to TestFlight, we conducted a systematic audit of every screen against the nine Apple App Store accessibility features. The findings were instructive — not because the agent had done no accessibility work, but because the gaps it left fell precisely into the categories where the agent's blind spots are sharpest.

**What the agent got right, without being asked:**
- Every unread badge was annotated with `.accessibilityLabel("N unread messages")`
- The jump-to-bottom scroll button had `.accessibilityLabel("Scroll to latest message")`
- The "Channel Rules" button had an explicit label
- The `ConnectionDot`'s connecting/reconnecting state used a `ProgressView()` spinner — a non-colour-only indicator — correctly
- Standard list controls, form fields, and labelled buttons all worked correctly out of the box

**What the agent missed:**
- The send button announced "arrow up circle fill button" to VoiceOver — the raw SF Symbol name, which is meaningless
- The `+` action menu announced "plus circle fill button"
- The `⋯` channel and server options menus had no labels
- The `ConnectionDot` static states (connected/disconnected/failed) were colour-only — green, gray, and red circles with no text or shape difference, invisible to colour-blind users and VoiceOver
- The password show/hide and copy buttons in onboarding had no labels
- The onboarding page indicator had no current-page announcement
- The `NetworkCard` selected state used colour and a checkmark icon but no accessibility trait or value
- `NSRegularExpression`-based mention highlighting was never tested for performance (see Section 4.5)
- `@Environment(\.accessibilityReduceMotion)` was never read anywhere in the app — every animation ran unconditionally
- The outgoing message bubble used `Color(hex: "0A84FF")` (#0A84FF) — a hardcoded blue with approximately 3.65:1 contrast against white text, failing WCAG AA (4.5:1 required for normal text)

The pattern: the agent applied accessibility labels to elements it understood as "important interactive controls" and skipped elements it conceptually categorized as "decorative" or "secondary" (icons-only buttons, state indicators, animations). This is a consistent and predictable blind spot.

### 8.2 Fixes Implemented

All material accessibility gaps were addressed in a dedicated accessibility pass. Changes were made to ten files:

**VoiceOver and Voice Control:**
- `MessageRowView`: Added combined `.accessibilityElement` with meaningful labels on incoming and outgoing bubbles ("`alice, 3:00 PM: Hello there`"), `.accessibilityAction(named: "Message options")` to expose the long-press context menu, and explicit labels on nick-tap buttons
- `InputBarView`: Added `.accessibilityLabel("Send message")` and `.accessibilityLabel("Attachments and commands")` to icon-only buttons
- `ServerRowView`: Added `.accessibilityLabel("Server options for Libera.Chat")` to the ellipsis menu and a descriptive hint to the nick-change button
- `ChatView`: Added `.accessibilityLabel("Show N members")` and `.accessibilityLabel("Channel options")` to toolbar buttons
- `ServerSidebarView`: Added `.accessibilityLabel("Settings")` to the gear button
- `ChannelRowView`: Added `.accessibilityLabel("Muted")` to the mute indicator icon
- `OnboardingView`: Added page-number/name announcement to the page indicator (`"Step 2 of 3 — Set Your Identity"`), labels on password show/hide and copy buttons, and `.accessibilityValue("Selected")`/`.accessibilityAddTraits(.isSelected)` to `NetworkCard`

**Differentiate Without Color Alone:**
- `ConnectionDot`: Added `.accessibilityLabel(accessibilityDescription)` to all states — "Connected", "Connection failed", "Disconnected" — so VoiceOver and colour-blind users are not dependent on green/red/gray alone

**Sufficient Contrast:**
- `Color+Theme.swift`: Replaced `sentBubble = Color(hex: "0A84FF")` (3.65:1 on white — fails WCAG AA) with an adaptive `UIColor` dynamic provider: `#0058D0` in light mode (6.35:1 ✓), `#409CFF` in dark mode (~4.8:1 ✓)

**Reduced Motion:**
- `InputBarView`: Autocomplete strip slide-in/out respects `@Environment(\.accessibilityReduceMotion)` — uses `.opacity` transition instead of `.move + opacity`
- `MessageListView`: Jump-to-bottom button appearance and `scrollToBottom()` both check `reduceMotion` — scale/spring replaced with opacity, animated scroll replaced with instant
- `MessageRowView`: Animation guard added for future animation additions
- `OnboardingView`: Page navigation `withAnimation` calls guarded by `reduceMotion`; decorative hero image marked `.accessibilityHidden(true)`

### 8.3 What Could Not Be Fixed Without Major Redesign

**Larger Text / message body font:** The message bubble font uses `.font(.system(size: messageFontSize))` driven by a user-adjustable slider in Appearance settings. This does not respond to the iOS system Accessibility → Larger Text setting. Fixing this properly would require either:
- Replacing the custom size slider with a Dynamic Type offset (e.g., `.font(.body)` scaled by a user preference multiplier), or
- Reading `UIApplication.shared.preferredContentSizeCategory` and mapping it to a size value

The supporting text throughout the app (nick headers, timestamps, system messages, list items) all use semantic Dynamic Type tokens and scale correctly. Only the main message bubble body text is affected.

**AvatarView contrast floor:** The `AvatarView` renders white initials on a colour generated deterministically from the nick string. Some generated colours (yellow tones, light greens) produce insufficient contrast against white text. Fixing this would require either a contrast check at generation time or switching to dark initials on light backgrounds.

### 8.4 Unit Tests Added

31 new accessibility tests cover the logic behind every fix — because the SwiftUI view modifiers themselves can't be verified in a headless test runner, the tests verify the *data* they depend on:

| Suite | Tests | What they verify |
|---|---|---|
| Connection state labels | 6 | All 5 states produce distinct, meaningful VoiceOver labels |
| Outgoing message label | 2 | Label includes sender, time, content; failure state annotated |
| Incoming message label | 4 | Grouped omits time; mentions annotated; no false annotation |
| Contrast ratios | 4 | New `#0058D0` light (6.35:1 ✓), old `#0A84FF` confirmed failed (<4.5:1), received bubble passes in both modes |
| Reduced motion | 3 | Motion-gated transitions use instant path when reduceMotion=true |
| Page indicator labels | 3 | Each page produces correct "Step N of 3 — Name" announcement |
| NetworkCard selection | 4 | Selected/not-selected values differ; encryption status in label |
| Server options label | 1 | Label includes server name |
| Member list label | 2 | Empty and populated states labelled correctly |
| Continue button hint | 2 | Disabled state explains why |

### 8.5 App Store Connect Accessibility Checklist

Based on the implemented changes, here is what can honestly be checked in App Store Connect:

| Feature | Status | Check? | Notes |
|---|---|---|---|
| **VoiceOver** | Supported | ✅ **Yes** | All interactive elements labelled; long-press context menu exposed via `.accessibilityAction`; connection state announced |
| **Voice Control** | Supported | ✅ **Yes** | All buttons reachable by spoken name; no icon-only unlabelled tap targets remain |
| **Larger Text** | Partial | ⚠️ **No** | Supporting text scales; message body text does not respond to system Larger Text setting |
| **Dark Interface** | Supported | ✅ **Yes** | Full system dark mode support; sent bubble now uses adaptive colour |
| **Differentiate Without Color Alone** | Supported | ✅ **Yes** | Connection states labelled; unread badges show numbers; mention highlight uses stripe + colour; network card uses checkmark + trait |
| **Sufficient Contrast** | Supported | ✅ **Yes** | Outgoing bubble: #0058D0 on white = 6.35:1 (WCAG AA ✓); incoming bubbles >10:1 in both modes |
| **Reduced Motion** | Supported | ✅ **Yes** | All animations in `MessageListView`, `InputBarView`, `OnboardingView` check `accessibilityReduceMotion` |
| **Captions** | N/A | ✅ **Yes** | Text-only app; no audio or video content |
| **Audio Descriptions** | N/A | ✅ **Yes** | No video content |

**Summary: 7 of 9 boxes can be honestly checked. "Larger Text" remains a partial implementation.**

---

## 9. Appendix

### A. Technology Reference

| Component | Technology | Notes |
|---|---|---|
| Language | Swift 5.10 | Actor-based concurrency throughout |
| UI | SwiftUI (iOS 17+) | NavigationStack, Combine-driven state |
| Networking | NWConnection | TLS + plaintext; actor-isolated |
| Concurrency | Swift actors, async/await, Combine | CheckedContinuation for CAP sync |
| Database | SQLite.swift | Versioned migrations, 6 phases |
| Project gen | XcodeGen 2.45.3 | `project.yml` source of truth |
| CI/CD | GitHub Actions (macOS 15) | Two-job: test then archive |
| Distribution | TestFlight + App Store Connect | Automated via `xcrun altool` |
| Agentic tool | OpenCode | Terminal CLI, TodoWrite task tracker |
| Model | Claude Sonnet (Bedrock) | `bedrock-claude-sonnet-4-6` |

### B. Nine Significant Bugs: Root Causes, Fix Attempts, and How Each Was Found

The "Caught by" column is particularly important: every runtime failure was found by a human running the app on a physical device. The two compilation failures that were caught only by CI were introduced by the agent itself while fixing a different bug.

| Bug | Symptom | Root cause | Fix attempts | Caught by |
|---|---|---|---|---|
| Actor deadlock in CAP negotiation | Messages appeared locally, never reached IRC server | Polling loop inside actor held execution context; `handleMessage()` starved | 3 (sleep → polling → CheckedContinuation) | Human on device |
| PASS sent to public servers | Connection silently died; sends failed | `server.password` (NickServ credential) sent as IRC PASS command to Libera.Chat | 3 (different code paths each time) | Human on device |
| CHATHISTORY before join confirmed | No chat history ever loaded | `CHATHISTORY` sent before `366 RPL_ENDOFNAMES`; server ignores it | 2 | Human on device |
| Single-slot callback overwrite | Messages dropped for non-active channels | `client.onMessage` overwritten on each channel switch | 3 (two patches, one architectural rewrite) | Human on device |
| DM navigation dead-end | "Send DM" returned to channel | Throwaway ViewModel + missing navPath push + wrong environment key | 3 | Human on device |
| `isFromCurrentUser` not persisted | Own messages appeared left-aligned after navigation | Field not in SQLite schema; loaded messages defaulted to `false` | 1 (clean fix once diagnosed) | Human on device |
| O(N²) history replay + per-render regex | App froze 10s then silently killed — no crash report (watchdog termination) | `rebuildDisplay()` called N times for N history messages; `NSRegularExpression` compiled per row per render | 1 (correct fix first try once diagnosed) | Human on device |
| `@Published private(set)` + Xcode 16.4 | CI compilation failure on 3 files | Xcode 16.4's Swift compiler rejects this property wrapper combination; Linux toolchain accepts it | 2 CI cycles | CI only — local tests passed |
| 5 `@Published` properties silently deleted | CI compilation failure — "cannot find X in scope" across 3 view files | Agent edit anchor spanned property declarations; replacement omitted them; no local test referenced them by name | 1 CI cycle | CI only — local tests passed |

### C. Sample Prompt Patterns

**Pattern 1: Protocol-specific constraint (effective)**
> "The IRC PASS command must only be sent when `server.useConnectionPassword == true`. Libera.Chat and other public networks do not use server-level passwords — they use SASL or NickServ for user authentication. Sending PASS to a public network causes `ERROR :Bad password` and an immediate connection close. Add a `useConnectionPassword: Bool` field to the `Server` model (defaulting to `false`) and gate the PASS command on that field in `IRCClientManager.connect()`."

This prompt names the exact protocol, the exact server behavior, the exact RFC command, and the exact code change required.

**Pattern 2: Symptom description with reproduction steps (effective)**
> "When I navigate from `#linux` to `#rust` and back to `#linux`, my own messages from the earlier session are now displayed on the left side (incoming style, gray bubble) instead of the right side (outgoing style, blue bubble). This only happens after navigating away — messages sent in the current session appear correctly. I believe `isFromCurrentUser` is not being restored correctly when messages are loaded from the database."

This prompt describes the observation precisely, identifies the trigger condition, and offers a hypothesis.

**Pattern 3: Vague intent (ineffective)**
> "Make sure authentication works when connecting to Libera.Chat."

This prompt has no protocol content, no specific failure mode, and no testable expected behavior. It produces an implementation that looks correct and fails at runtime.

**Pattern 4: Architecture framing (effective)**
> "The current design has `ChannelViewModel.registerCallbacks()` overwriting `client.onMessage` each time a new channel view opens. When the user switches channels, the previous channel's callback is overwritten. When `stop()` is called on navigate-away, `client.onMessage` is set to nil. This means any channel that isn't currently visible receives no messages. The fix is to move all `client.onXxx` registrations into `IRCClientManager.connect()` permanently and publish via per-server Combine subjects. `ChannelViewModel` subscribes to these subjects instead of writing to `IRCClient` directly."

This prompt identifies the exact failure mode in the current architecture, explains why it fails, and specifies the correct architectural pattern.

### D. OpenCode: Tool Notes

OpenCode operates as a terminal CLI that maintains a persistent conversation with the underlying model. Key behaviors relevant to this project:

**TodoWrite task tracking**: Before implementing a multi-step plan, the agent can populate a task list that it updates as work proceeds. This is not cosmetic — it prevents the agent from losing track of sub-tasks in long sessions and provides the human with a progress view.

**Read-before-edit discipline**: OpenCode reads files before editing them and refuses to edit files it hasn't read in the current session. This prevents the most common class of agentic edit failures (editing based on a stale mental model of a file's current content). It does not, however, verify that an edit preserved all content that was in the original — only that the `oldString` anchor was found and replaced.

**Parallel tool calls**: For independent operations (reading multiple files, running multiple searches), OpenCode batches tool calls in a single turn. This reduces session latency significantly on multi-file analysis tasks.

**CI integration**: The agent can monitor GitHub Actions run status via `gh run watch` and parse compilation errors from log output, enabling a tight edit/build/diagnose loop without human mediation for compilation failures.

### E. Unit Tests the Agent Should Have Written But Didn't

This appendix documents specific tests that would have caught real bugs before they reached a device or CI. They are presented not as criticism but as a practical pattern library for teams directing agents on similar projects.

**E1 — Call-count test for batch operations (would have caught O(N²) crash)**

```swift
// This test would have caught the O(N²) rebuildDisplay() bug.
// The agent wrote tests asserting rebuildDisplay() produced correct output.
// It never wrote a test asserting how many times it was called.
func testHistoryBatchCallsRebuildOnce() {
    var rebuildCount = 0
    let vm = ChannelViewModel(...)
    vm.onRebuildDisplay = { rebuildCount += 1 }  // inject a counter

    // Simulate 100 history messages arriving (a realistic CHATHISTORY batch)
    for i in 0..<100 {
        vm.receiveHistoryMessage(makeMessage(i))
    }
    vm.flushHistoryBatch()  // batch end event

    XCTAssertEqual(rebuildCount, 1,
        "rebuildDisplay() must be called exactly once per batch, not once per message")
}
```

**E2 — Render-phase purity test (would have caught per-render regex compilation)**

```swift
// Computed properties on View structs execute on every layout pass.
// This test verifies isMention doesn't compile a new regex each time.
func testIsMentionUsesRegexCache() {
    var compileCount = 0
    let originalInit = NSRegularExpression.init
    // Inject a counter (or use the NSCache directly)

    for _ in 0..<100 {
        _ = isMention(content: "hey alice", nick: "alice")
    }

    XCTAssertEqual(compileCount, 1,
        "isMention must compile the regex once and cache it, not once per call")
}
```

**E3 — Symbol existence test (would have caught silent property deletion)**

```swift
// A trivial test that references every @Published property by name.
// If any property is accidentally deleted during an edit, this test
// fails to compile immediately — before CI, before any human runs the app.
func testChannelViewModelPublishedPropertiesExist() {
    let vm = ChannelViewModel(serverId: "s", channelName: "#test", ircManager: .shared)
    // Just access them — the test is the compilation, not the assertion
    _ = vm.displayMessages
    _ = vm.topic
    _ = vm.members
    _ = vm.isLoadingHistory
    _ = vm.currentNick
    _ = vm.unreadCount
    _ = vm.failedMessageIds
    _ = vm.rulesURL
}
```

**E4 — Platform behavior test (would have helped surface Xcode 16.4 incompatibility)**

```swift
// Tests that use @ObservedObject subscript syntax will fail on Xcode 16.4
// if @Published properties use private(set) — even if the Linux toolchain passes.
// Writing a test that uses the projected value ($vm.members) exercises the
// exact type-checker path that was broken.
func testChannelViewModelObservableBinding() {
    let vm = ChannelViewModel(...)
    let binding = Binding(get: { vm.members }, set: { _ in })
    XCTAssertNotNil(binding)
    // If @Published private(set) breaks @ObservedObject, this fails to compile
}
```

The pattern in E1, E2, and E3 is the same: the agent wrote tests for "what does this function return" but not "how does this function behave when called in the way the real system calls it." Directing the agent explicitly to write call-count tests, render-phase purity tests, and symbol existence tests for every major component would have caught all three of the post-fix regressions without any CI cycles.

*Parso Consulting — April 2026*

*The source code for Parso IRC, including the full commit history, CI configuration, and unit test suite described in this whitepaper, is available at the project repository.*
