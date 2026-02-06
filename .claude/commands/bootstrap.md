Let's start a new project.

Begin by copying everything recursively from ../template to this project
folder, then update the project name in all project files in this folder
to the name of the current project.

When that is complete, I have an idea I want to talk through with you.
I'd like you to help me turn it into a fully formed design and spec 
(and eventually an implementation plan). Enter planning mode.

Review the readme file if it exists. If not, ask me what we're going to build
to understand where we're starting off. Then ask me questions, one at a time, 
to help refine the idea. Ideally, the questions would be multiple choice, but 
open-ended questions are OK, too.

Don't forget: only one question per message. Once you believe you understand 
what we're doing, stop and describe the design to me, in sections of maybe 
200-300 words at a time, asking after each section whether it looks right 
so far.

Once that thinking session is complete, and before starting the build of the 
current project, I need your help to write out a comprehensive implementation 
plan. Assume that the engineer has zero context for our codebase and 
questionable taste. document everything they need to know. which files to 
touch for each task, code, testing, docs they might need to check. how to test 
it.

Give them the whole plan as numbered phases broken into bite-sized, numbered
tasks. DRY. YAGNI. TDD. Frequent commits. Assume they are a skilled developer,
but know almost nothing about our toolset or problem domain.
Assume they don't know good test design very well.

Please write out this plan, in full detail, into docs/plans/

After writing the detailed implementation plan, create a PHASES_SUMMARY.md file
in docs/plans/ that provides a high-level overview of all phases. This summary
should include:
- Each phase number, title, and goal
- List of tasks per phase (brief descriptions)
- Key deliverables for each phase
- Technology stack overview
- Key principles (YAGNI, DRY, TDD)
- Success criteria
- Post-launch maintenance guidance

The PHASES_SUMMARY should match the detailed plan exactly but be more concise,
serving as a quick reference guide to the implementation roadmap.

At the end of the detailed implementation plan, include a "Next Steps" section
with ideas for future enhancements beyond the initial launch. Each enhancement
idea should be clearly flagged with either [Keith's idea] or [Claude's idea]
to indicate its source. These are optional improvements that could be tackled
after the core site is launched and stable.
