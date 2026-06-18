# Recruit (`recruit`)

> Applicant Tracking System: `Vacancy` pipelines, `Candidate` talents, `Applicant` cards, plus `Review`/`Opinion` interviews.

## Where in code
- `plugins/recruit/src/index.ts` -- plugin id (`recruitId = 'recruit'`), class/mixin ids
- `plugins/recruit/src/types.ts` -- document interfaces (`Vacancy`, `Candidate`, `Applicant`, `Review`, `Opinion`, `VacancyList`, `ApplicantMatch`)
- `models/recruit/src/index.ts` -- model (`T*` classes, viewlets, kanban, actions)
- `models/recruit/src/{types,review,spaceType,permissions}.ts` -- model classes, interview model, vacancy project type
- `plugins/recruit-resources/` -- UI

## Purpose
A full ATS on the task substrate. A `Vacancy` is a `task.Project` (the hiring pipeline); an
`Applicant` is a `task.Task` linking a `Candidate` to a `Vacancy` with a pipeline `status`;
`Review`s (interviews, which are `calendar.Event`s) and `Opinion`s capture interview outcomes.
Tier-2 mobile feature.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Vacancy` | `task.Project` | `fullDescription: MarkupBlobRef \| null`, `company?: Ref<Organization>`, `dueTo?`, `location?`, `number`, `polls?` | A hiring pipeline (the space). |
| `Candidate` (mixin) | `contact.Person` | `title?`, `applications?`, `onsite?`, `remote?`, `source?`, `skills?`, `reviews?`, `polls?` | "Talent" — a person marked as a candidate. |
| `Applicant` | `task.Task` | `space: Ref<Vacancy>`, `attachedTo: Ref<Candidate>`, `status: Ref<Status>`, `startDate`, `polls?` | An application card; `status` = pipeline stage. |
| `Review` | `calendar.Event` | `attachedTo: Ref<Candidate>`, `number`, `verdict`, `application?`, `company?`, `opinions?` | A scheduled interview (a calendar event). |
| `Opinion` | `core.AttachedDoc` | `attachedTo: Ref<Review>`, `number`, `value`, `description: Markup`, `comments?` | An interviewer's opinion attached to a review. |
| `VacancyList` (mixin) | `contact.Organization` | `vacancies: number` | Marks an org as having vacancies. |
| `ApplicantMatch` | `core.AttachedDoc` | `attachedTo: Ref<Candidate>`, `complete`, `vacancy`, `summary`, `response` | AI/match result against a vacancy. |

## Key relationships / mixins
- `Candidate` is a **`Mixin` on `contact.Person`** and `VacancyList` a **`Mixin` on
  `contact.Organization`** — talents and hiring companies are contacts with mixins applied.
- `Applicant extends task.Task` (inherits `assignee`, `status`, `rank`, `number`); `Vacancy extends
  task.Project` with a `VacancyType` `ProjectTypeDescriptor` defining stages + the `Applicant`
  `TaskType`.
- `Review extends calendar.Event`, so interviews appear on the calendar and carry start/end/reminders.
- `Skills` use the [tags](tags.md) system (`TagElement`/`TagReference`); `Candidate.skills` counts them.
- Activity mixin + `ActivityExtension` on `Vacancy`, `Applicant`, `Review`, `Candidate` enable
  comments. `ClassCollaborators` set for `Vacancy` (createdBy) and `Applicant` (createdBy, assignee).
- Gmail integration mixed in for candidate email threads.

## Notable actions/flows
- Kanban over `Applicant` grouped by `status` within a `Vacancy`. `CreateTalent` / `CreateCandidate`
  applies the `Candidate` mixin to a person. `CreateApplication` adds an `Applicant`.
- Interview scheduling creates a `Review` (calendar event); reviewers add `Opinion`s; the `Review`
  rolls up a `verdict`.

## Mobile relevance
Tier 2. The richest Tier-2 app: kanban of applicants, candidate profiles (contact + mixin + skills),
interview events on the calendar, resume blobs via datalake. Candidate/VacancyList are mixins —
resolve through `contact`. Reuse generic task + calendar rendering.

## Cross-references
- Plugins: [task](task.md), [contact](contact.md) (Candidate/VacancyList mixin targets), [tags](tags.md) (skills), [activity](activity.md), [attachment](attachment.md) (resumes), [view](view.md)
- Concepts: [data-model](../concepts/data-model.md) (mixins), [transaction-model](../concepts/transaction-model.md)

## Gotchas
- `Candidate` and `VacancyList` are mixins on contacts, not standalone classes — query via
  `contact.Person` / `contact.Organization` filtered by the mixin.
- `Review` is a `calendar.Event`; interview times/recurrence come from the calendar model, not recruit.
- `Applicant.attachedTo` is a `Candidate` (mixed-in person); resolve through contact to render.
