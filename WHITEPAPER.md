# Agentic Coding in Practice: Lessons from Building a Production iOS Application

### A Practitioner Report from Parso Consulting

**April 2026**

---

## Executive Summary

Over twelve days, a two-person senior engineering team produced a fully functional, App Store–submitted iOS application using an agentic coding workflow. The team wrote zero lines of application code. All 14,400 lines were produced by the agent. Our estimate is that conventional development of an equivalent application would require six to eight weeks — representing a roughly 4–5x acceleration in calendar time.

The efficiency gain is real. The preconditions for realizing it are specific, demanding, and frequently misunderstood.

**Frontier-class models are the minimum viable capability.** Smaller open-source models produced plausible code that did not function. The gap between model tiers is not incremental — it is categorical. Teams that evaluate agentic coding with demonstration-grade models and then deploy with production-grade ones will find the results incomparable in both directions.

**"Vibe coding" requires senior engineers, not junior ones.** The agent is an exceptionally fast and knowledgeable implementer. It is not a domain expert. Effective prompts embedded precise technical specifications — protocol behaviors, sequencing constraints, architectural requirements — that came from human research. The bottleneck shifted from writing code to directing code, which requires the same judgment senior engineers have always provided.

**The plan/build/test cycle is not optional overhead — it is the method.** Every feature required at least one complete cycle of planning, implementation, CI validation, and device testing. Compressing any step produced regressions that compounded. The cycle cannot be shortcut; it can only be made faster.

**Unit tests must be explicitly directed.** The agent produced 232 tests covering functional correctness. It did not spontaneously write tests for performance characteristics, render-phase invariants, or symbol existence. Each of these gaps allowed a real failure to reach a user. Human direction on test type and scope is not optional.

**Substantial plumbing remains entirely manual.** Apple developer accounts, code-signing certificates, provisioning profiles, App Store Connect configuration, and GitHub Actions secret management are outside the scope of any current agentic tool. For iOS specifically, this infrastructure consumed approximately seven hours — entirely separate from development time. Teams should budget for it accordingly and not include it in agentic productivity estimates.

**The return on investment is real for teams prepared to use it correctly.** Agentic coding amplifies senior engineering capacity. It does not reduce the need for it.

---

## 1. What Was Built and How

### 1.1 The Project

Parso IRC is a native iOS IRC client targeting twenty-five public networks including Libera.Chat, OFTC, and EFnet. It implements the IRC protocol (RFC 1459) and several IRCv3 extensions, and delivers a full channel and direct-message interface with persistent history, unread badges, background reconnection, member lists, channel browsing, and a three-page onboarding flow. The app was submitted to the Apple App Store at the close of the project period.

The project ran from April 9 to April 21, 2026 — twelve calendar days. At completion: 55 Swift source files, approximately 14,400 lines of production code, 232 unit tests, and a fully automated CI/CD pipeline deploying to TestFlight on every commit to `main`. The application passes all nine Apple App Store accessibility requirements.

### 1.2 The Tool and Model

We used a terminal-based agentic coding CLI operating at the task level: reading files, proposing plans, writing code, running shell commands, and monitoring CI output — all in response to natural language prompts. Unlike IDE-integrated completion assistants, the tool maintains a persistent conversation context across a session and decomposes complex requests into tracked sub-tasks. It is a qualitatively different class of tool from autocomplete.

The underlying model was a frontier-class large language model accessed via a cloud API. The choice of model tier proved to be the single most consequential infrastructure decision of the project — discussed further in Section 3.

We also note that a broader market context is relevant here. A spectrum of AI coding tools now exists: completion assistants (suggesting lines or functions), chat-based pair programmers (answering questions about code), IDE-integrated agents (operating within an editor), and fully autonomous coding agents (capable of planning, editing, testing, and iterating across an entire codebase). This project used the last category. The distinctions matter because the capabilities, failure modes, and required human skills differ substantially across them.

### 1.3 The Workflow

We never attempted to one-shot a feature. Every significant piece of work followed a consistent five-step cycle:

1. **Plan** — present the problem, ask the agent to read the relevant files and produce a complete implementation plan before writing a line of code
2. **Build** — implement the plan; the agent edits files, runs the unit test suite, and reports results
3. **CI** — every commit triggers a full build pipeline; the agent monitors output and fixes compilation errors
4. **Device test** — a human installs the build on an iPhone and observes runtime behavior
5. **Iterate** — return to step 1 for the next issue

The cycle was not optional. Skipping device testing meant visual bugs persisted. Skipping the planning phase meant implementations that were locally correct but architecturally wrong. The sessions where we followed this discipline precisely were the sessions with clean commits and no regressions.

### 1.4 The Prompting Principle

The single most important determinant of output quality was prompt specificity. The gap between an ineffective and an effective prompt is not subtlety — it is an order of magnitude of technical precision.

A prompt like "add chat history support so I can see previous messages" produced an implementation that failed silently on every real server. A prompt that specified the exact IRC numeric reply (366 RPL_ENDOFNAMES), the exact server-side constraint (CHATHISTORY must only be sent after the JOIN is confirmed), and the exact code change required (wire a callback to that numeric, not to the channel open event) produced a correct implementation on the first attempt.

The principle: the agent implements what it is told precisely. It does not infer domain-specific behavioral constraints from intent descriptions. Domain knowledge must come from human research and be embedded explicitly in the prompt. This was true across every protocol feature, every Apple platform constraint, and every architectural pattern in the project.

---

## 2. Where Agentic Coding Delivers Value

### 2.1 Architecture and Concurrency

The agent's most valuable capability was producing correct software architecture for non-trivial concurrent systems — once the problem was correctly framed.

When a design flaw caused messages for non-active channels to be silently dropped, the agent correctly diagnosed the root cause: a single-slot callback design being overwritten on every channel switch. It proposed and implemented a complete architectural replacement — a Combine-based fan-out where a manager class owns permanent callbacks and individual view models subscribe — without human involvement in the implementation details. This replacement touched approximately 1,500 lines across two files and was architecturally correct on the first attempt after the problem was described precisely.

Similarly, when a Swift actor deadlock caused the IRC registration handshake to time out (a polling loop holding the actor, preventing the message handler it was waiting for from running), the agent correctly diagnosed the concurrency model violation and implemented a `CheckedContinuation`-based solution with properly isolated timeout helpers. No concurrency specialist human time was spent on the fix.

The pattern: the agent reasons correctly about complex system interactions when given a precise description of the failure. It does not spontaneously notice that a design decision in one component will create a correctness failure six features later. Human framing of the problem is always required; human implementation of the solution often is not.

### 2.2 Infrastructure and Test Generation

The agent produced the entire CI/CD pipeline — a 200-line GitHub Actions workflow with dynamic iOS Simulator detection, dependency caching, a two-job architecture (tests must pass before the archive runs), and graceful credential cleanup. The human's contribution was providing the seven secret values (certificates, provisioning profiles, API keys). The agent handled all structural decisions.

The agent also produced 232 unit tests covering protocol parsing, authentication flows, message routing, concurrency behavior, accessibility label logic, and contrast ratio correctness. For every significant bug fixed, it wrote a corresponding regression test named after the failure mode — creating a test suite that functions as a living record of the project's defects.

### 2.3 The Collaboration Model

The working app is not the product of the agent alone, nor of the human alone. It is the product of a specific division of labor that neither party could have replicated independently.

The agent contributed: all 14,400 lines of application code, correct diagnosis of most failures once symptoms were described precisely, sound architectural designs at the component level, comprehensive regression tests, and the full CI/CD pipeline. The human contributed: domain protocol research (IRC RFC 1459, IRCv3 extensions), on-device testing (every runtime failure was found by a human running the app on a physical device), articulation of visual symptoms the agent could not observe, and persistence through the agent's own self-inflicted regressions. The agent alone would never have noticed the app freezing and being killed by the iOS watchdog. The human alone could not have written 14,400 lines of Swift in twelve days.

This is the correct mental model for current agentic coding: not automation, but acceleration. The agent is an extremely fast, extremely knowledgeable implementer with significant blind spots. The human is the domain expert, quality assurance function, and error-recovery supervisor. Neither role is optional.

---

## 3. Where Human Judgment Remains Indispensable

Agentic coding introduces three categories of risk that traditional development practices do not fully address. Each requires an active human mitigation strategy.

### 3.1 Domain Blindness

The agent applies general knowledge to domain-specific constraints it cannot verify. The most consequential example in this project: the app's outgoing messages appeared locally but never reached the IRC server — across three separate sessions. The root cause was the same each time. The agent was sending an IRC `PASS` command to Libera.Chat, a public network that doesn't use server-level passwords. Libera.Chat responds to an unexpected `PASS` with an immediate connection termination. The agent had no way to know this from general knowledge, and no amount of prompting "make sure authentication works" surfaced it. The fix required a human to research how IRC network authentication differs from server-level authentication, and to translate that research into a precise architectural change.

This pattern recurred across every protocol feature, every Apple platform constraint, and every external API integration in the project. The agent implements correctly what it is told. It cannot independently verify behavioral expectations against external systems it has no access to.

**Implication:** For any project involving a non-trivial external protocol, API, or platform constraint, budget explicit research time for a human to understand that domain and translate it into prompts. Do not assume general LLM knowledge is sufficient for domain-specific correctness.

### 3.2 Visual and Runtime Opacity

The agent cannot see the running application. Every failure that only manifests visually — a button that doesn't navigate correctly, a message appearing on the wrong side of the screen, a member list that is blank because data arrived after the sheet opened — requires a human to observe it, articulate it precisely, and guide the agent to the root cause in code.

In this project, every one of the nine significant runtime failures was first detected by a human running the app on a physical device. None were detected by the agent reviewing its own code. The agent could read code that contained the bug without noticing it; the bug only became visible in execution.

**Implication:** Every agentic iOS (or any UI-intensive) development cycle requires a dedicated device-testing phase with a human tester. The agent's test suite is not a substitute. Budget for it as a first-class project activity, not as an afterthought.

### 3.3 Integration-Scale Performance

Components that are individually correct can be collectively catastrophic under realistic load. The agent assembled a message display pipeline in which a rebuild function was called once per incoming message — including during batch history replay of 100 messages. The rebuild function iterates all accumulated messages. The result was O(N²) work on the main thread. Simultaneously, a mention-detection function compiled a fresh regular expression on every render of every message row. Under realistic load, the app froze for ten seconds and was terminated by the iOS watchdog process — silently, with no crash report, producing only an "App Quit Unexpectedly" dialog.

The agent wrote 191 tests before this happened. Every test passed. Not one of them modeled the integrated rendering pipeline under batch load. The agent assembled individually-correct pieces in a way that was collectively catastrophic, and its own test suite was structurally incapable of catching it.

**Implication:** Human review of hot paths — message lists, render-phase computed properties, event-driven batch operations — is required on any performance-sensitive feature. The agent does not spontaneously reason about computational complexity in integrated contexts. See Section 4 for specific test strategies.

---

## 4. The Testing Imperative

Unit tests matter more for agentic coding than for any other development approach — and the agent will not write the right ones without explicit human direction.

### 4.1 What the Agent Tests and What It Doesn't

The agent produces tests for functional correctness: given this input, produce this output. These tests are valuable and the agent writes them diligently. What it does not write, unless explicitly directed:

- **Performance path tests:** how many times is this function called under realistic load, not just whether it produces correct output once
- **Render-phase invariants:** whether computed properties on view structs perform expensive operations (regex compilation, object allocation, database calls) that execute on every layout pass
- **Symbol existence tests:** trivial tests that reference every public property and method by name, which fail to compile immediately if a property is accidentally deleted during a refactor
- **Platform behavior tests:** tests that exercise Swift type annotations or property wrappers in the exact configuration that the production compiler (Xcode 16.4 on macOS) will evaluate, rather than a cross-platform test runner (Linux `swift run`) that accepts a superset

Each of these gaps allowed a real failure to reach production in this project. The O(N²) watchdog crash was not caught because no test counted function calls under batch load. A silent deletion of five core observable properties from a view model was not caught locally because no test referenced those properties by name — it was caught only when CI ran the real Xcode compiler.

### 4.2 The Edit Anchor Problem

The agent's editing process can silently delete code it did not intend to remove. When making a targeted change to a file, the agent identifies an edit location using a text anchor and replaces a surrounding block. If that block contains declarations beyond what was intended to change, and the replacement omits them, they are silently removed. The agent does not diff its edit against the original to verify that only the intended symbols were modified.

In one instance, an edit intended to fix a Swift property wrapper combination accidentally removed the declarations for five observable properties — `members`, `currentNick`, `isLoadingHistory`, `unreadCount`, and `failedMessageIds` — from the primary view model. The local test suite passed. CI failed with 17 compilation errors. A human had to prompt "check the build."

The defense is a test suite comprehensive enough to catch what disappears. A test that references a symbol by name fails to compile the moment that symbol is removed. These tests require no assertions — the compilation itself is the test. The agent will write them if directed; it will not write them by default.

### 4.3 The Test Environment Gap

The local test runner and the production build environment are not the same. In this project, unit tests ran on a Linux Swift toolchain. The production build ran on Xcode 16.4 on macOS. Several Swift property wrapper combinations that compile cleanly on Linux are rejected by Xcode's type checker. The agent, having no access to a macOS build, committed platform-specific failures with confidence because its local runner passed.

The structural fix is to run a compilation check in the production build environment on every commit — not just a language-level test runner. For iOS this means `xcodebuild build` in CI, not just `swift run` locally. The faster the feedback loop between "agent edits code" and "code is verified against the real compiler," the fewer wasted CI cycles.

**The practical rule:** direct the agent explicitly on all four test categories above — call-count, render-phase, symbol existence, and platform behavior. Treat any edit touching Swift type annotations or property wrappers as "must be verified by CI before considering complete."

---

## 5. Key Findings for Technology Leaders

**Finding 1: Frontier-class models are a capability floor, not a point on a continuum.**
Teams that tested agentic coding with smaller open-source models encountered code that compiled but did not function — UI elements with no backing logic, protocol implementations that were structurally plausible but semantically wrong, multi-file edits that introduced contradictions the model could not resolve. The gap to frontier-class models is categorical, not incremental. Evaluate with the model you intend to deploy, at the scale of the application you intend to build. Toy examples are not predictive.

**Finding 2: Agentic coding increases the leverage of senior engineers and does not reduce the need for them.**
The bottleneck shifts from writing code to directing code. Directing code requires the same domain knowledge, architectural judgment, and quality intuition that senior engineering has always demanded — now applied to prompt specification and output review rather than implementation. "Hire a junior engineer and give them an AI assistant" is the wrong model. "Give a senior engineer a 4–5x implementation throughput multiplier" is the right one. Teams should plan staffing accordingly.

**Finding 3: The plan/build/test cycle is the fundamental unit of work.**
Successful sessions — those that produced clean, working features without compounding regressions — all followed the same five-step cycle: plan, build, CI, device test, iterate. Failed sessions all skipped or compressed a step. The cycle adds overhead that feels like inefficiency; it is in fact the mechanism that makes the acceleration sustainable. It cannot be shortcut; it can only be internalized.

**Finding 4: Manual plumbing is a separate budget item, not a rounding error.**
For this project — a single iOS application — establishing the infrastructure outside the agent's reach (Apple developer account, distribution certificate, provisioning profile, App Store Connect record, GitHub Actions secrets) required approximately seven hours of experienced engineer time, with a 24–48 hour approval delay. For teams new to the Apple ecosystem, two to three days is realistic. This cost does not decrease as the agent improves. It is a platform constraint, not a tooling gap. Account for it explicitly in project estimates.

**Finding 5: Unit tests directed by humans, written by the agent, are the most durable risk mitigation available.**
A test suite that covers functional correctness, performance path behavior, symbol existence, and platform-specific constraints is the most effective protection against the three risk categories described in Section 3. The agent will write high-quality tests across all four categories when explicitly directed. Left to its own judgment, it writes correctness tests and misses the rest. The human's job is not to write the tests — the agent does that — but to specify which properties to test. This is a skill that can be learned and systematized.

---

## 6. Is Your Team Ready? A Practical Framework

Before committing to an agentic coding workflow for a production project, leadership should be able to answer yes to each of the following:

1. **Do you have at least one senior engineer to direct the agent?** The quality of output is bounded by the quality of direction. An engineer who cannot identify an incorrect architectural proposal, recognize a missing test category, or articulate a visual runtime failure to the agent in precise technical terms cannot effectively use the tool.

2. **Can you specify your domain requirements precisely?** If the project involves external protocols, regulated APIs, or platform-specific behaviors, someone on the team must understand them well enough to embed that knowledge in prompts. General LLM knowledge is insufficient for domain-specific correctness.

3. **Do you have a CI pipeline, or can you build one?** The feedback loop between "agent edits code" and "code is verified against the production compiler" is the primary quality control mechanism. Without it, platform-specific failures and silent regressions accumulate. This is not optional.

4. **Can you physically test the application on a target device?** Every visual and runtime failure in this project was found by a human running the app. The agent's tests are not a substitute. If your team cannot test on a real device, you will not find the most consequential failures until users do.

5. **Do you have, or can you create, the required platform infrastructure?** For iOS: an Apple Developer Program membership, a distribution certificate, a provisioning profile, and the requisite App Store Connect setup. For other platforms, the equivalent. The agent writes the code that consumes this infrastructure; it cannot generate the infrastructure itself.

6. **Are your requirements greenfield or well-specified?** Agentic coding is most effective for new applications with clear functional requirements. Existing systems with undocumented behavior, legacy data models, or unwritten institutional knowledge present substantially higher risk — the agent cannot reason about what it cannot read.

**For startups building consumer apps:** a two-person senior team with this framework in place can realistically produce a deployable application in one to two weeks. The efficiency gain over conventional development is genuine. Avoid the temptation to staff down on the assumption that the agent replaces engineering headcount — it amplifies it.

**For enterprise consulting teams:** agentic coding is viable for greenfield internal tooling with well-defined requirements. For complex legacy systems, the risk profile is higher and the ROI less clear. Expect to invest in prompt engineering as a distinct skill. Do not commit to "hours not weeks" timelines with clients until the specific preconditions above are met.

**For AI tooling and platform teams:** the three gaps with the largest impact on ROI are automated UI verification (closing the feedback loop between code and rendered output), plumbing automation (certificate lifecycle, secret management, app store configuration), and production-equivalent test environments. Teams solving any of these three problems will have a measurable effect on the economics of agentic development.

---

## 7. Looking Ahead

Three developments would materially change the ROI equation for agentic coding.

**Automated UI verification.** The agent's largest structural blind spot is the rendered interface. Any capability that closes the loop between "agent writes UI code" and "agent observes the result" — through accessibility tree inspection, simulator screenshot diffing, or interactive UI testing — would directly address the most persistent failure category in this project and likely in the industry. This is the highest-value unmet need.

**Plumbing automation.** The manual infrastructure boundary (code signing, app store credentials, developer account management) is currently fixed and well-defined. It is a solved problem in principle — every step is automatable — but no current toolchain automates it end-to-end for iOS. The team that does will eliminate the most friction-intensive phase of any mobile agentic development project.

**Production-equivalent local test environments.** The gap between a cross-platform language test runner and the production build environment (platform-specific compilers, UI framework type checkers, device simulators) costs CI cycles and human attention on every project. Tooling that gives the agent access to a production-equivalent compilation signal locally — before a commit is pushed — would eliminate an entire category of avoidable regressions.

The direction of travel is clear. The pace is faster than most practitioners expect. Teams building the skills and infrastructure for agentic coding today will have a meaningful capability advantage within twelve months.

---

## Appendix A: Project Metrics

| Metric | Value |
|---|---|
| Calendar days | 12 (April 9–21, 2026) |
| Production lines of code | ~14,400 (55 Swift files) |
| Unit tests | 232 across 26 suites |
| CI builds triggered | ~220 |
| CI build failure rate | ~8% |
| Major architectural rewrites | 3 |
| Significant bugs requiring 3+ fix attempts | 6 |
| Human application code written | 0 lines |
| Platform plumbing (estimated) | ~7 hours |
| Estimated conventional development time | 6–8 weeks |
| Estimated calendar-time acceleration | ~4–5x |

The 8% CI build failure rate — approximately four times the 1–2% typical of mature engineering teams — reflects a structural property of the agent's editing process rather than a tooling deficiency. The agent cannot verify platform-specific compilation behavior locally; CI is its production compiler. Investing in faster CI feedback loops and more comprehensive local test coverage directly reduces this rate.

The zero lines of human application code is an accurate count, not a rounding approximation. It does not include the prompts, research notes, device-testing observations, and architectural direction that were the human's actual contribution — none of which are lines of code, but all of which were essential.

---

## Appendix B: References and Resources

The following resources were directly used in this project or are recommended for teams evaluating a similar approach.

**Agentic Coding Platform**
OpenCode was used as the agentic coding platform for this project. Source code and documentation are available at https://github.com/anomalyco/opencode

**Model**
Claude Sonnet (Anthropic) on Amazon Bedrock was the frontier-class model used. Documentation at https://docs.anthropic.com/en/docs/about-claude/models/overview and https://aws.amazon.com/bedrock/claude/

**Lower-Capability Model References**
MiniMax 2.5 (https://www.minimaxi.com) and Qwen (Alibaba, https://qwen.readthedocs.io) were representative of the smaller open-source model tier evaluated during this project.

**Project Repository**
The Parso IRC source code, full commit history, CI configuration, and complete unit test suite referenced throughout this paper are available at https://github.com/johnarleyburns/parso-irc-ios-app

**Supporting Standards**
- IRCv3 capability negotiation and CHATHISTORY specification: https://ircv3.net/specs/extensions/chathistory
- WCAG 2.1 contrast ratio guidelines: https://www.w3.org/TR/WCAG21/#contrast-minimum
- Apple Human Interface Guidelines — Dynamic Type sizes: https://developer.apple.com/design/human-interface-guidelines/typography

---

*Parso Consulting — April 2026*
