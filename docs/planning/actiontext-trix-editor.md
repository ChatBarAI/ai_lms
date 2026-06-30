# Planning: ActionText + Trix as the AI LMS rich-text editor

**Status:** Implemented (2026-06-30)

### Implementation log

| Phase | Done | Notes |
|---|---|---|
| Model + migration | ✅ | `has_rich_text :body`; `20260630000000_migrate_lesson_body_to_action_text.rb` |
| Forms & views | ✅ | Trix on `_form`, ActionText render on `show`, `to_plain_text` on `_card` |
| Tests & fixtures | ✅ | `action_text/rich_texts.yml`; `plain_text_to_action_text_test.rb` |
| Manual QA | ☐ | See section 9 checklist in browser |

**Created:** 2026-06-30  
**Target:** Single PR (or small PR series) replacing any CKEditor direction with Rails-native ActionText + Trix

---

## 1. Decision summary

We should **not** adopt CKEditor 5 for AI LMS. Instead, we standardise on **ActionText + Trix**, which ships with Rails, is fully MIT-licensed, and requires no third-party CDN or commercial licence management.

| Criterion | CKEditor 5 | Trix (via ActionText) |
|---|---|---|
| Licence | [GPL / commercial dual licence](https://github.com/ckeditor/ckeditor5/blob/master/packages/ckeditor5/LICENSE.md) — not MIT | [MIT](https://github.com/basecamp/trix) |
| AI LMS licence fit | Poor — GPL/commercial terms conflict with our MIT distribution model | Excellent — same permissive licence family |
| Self-hosting | Possible but non-trivial; freemium features and build tooling add operational cost | Bundled via importmap; no external service |
| Rails integration | Custom wrapper gem / JS wiring | First-class: `has_rich_text`, `rich_text_area`, ActiveStorage attachments |
| Maintenance | Vendor release cycle, licence audits | Rails + Basecamp ecosystem |

**Recommendation:** Proceed with ActionText + Trix per the [Rails Action Text overview — Customizing the rich text content editor (Trix)](https://guides.rubyonrails.org/action_text_overview.html#customizing-the-rich-text-content-editor-trix).

---

## 2. Guide: current vs goal — pages to check first

Read this section **before** touching code. It tells you which URLs to open in the browser, what you should see today, and what will change after the PR.

### 2.1 Mental model (30 seconds)

AI LMS has **two different places** where instructors write long-form content:

| Concept | What it is | Editor today | After this PR |
|---|---|---|---|
| **Lesson body** | Main description on the lesson page (under the title / video) | Plain textarea — no toolbar, no bold/lists | **Trix** (same as materials) |
| **Lesson material (Rich text kind)** | Optional extra reading attached to a lesson (PDF, audio, etc.) | **Trix already** | No change — this is the reference UI |

This PR only changes the **lesson body** row in the table above. Everything else in the app stays as-is for now.

```
Lesson page
├── Intro video
├── Lesson body          ← THIS PR (plain text → Trix)
├── AI tutor widget
├── Materials section    ← already uses Trix for "Rich text" materials
└── Quiz
```

### 2.2 Before you start

1. Run the app locally (`bin/dev` or `bin/rails server`).
2. Log in as **instructor** (seeded dev account):
   - Email: `instructor@example.com`
   - Password: shown when you ran `bin/setup` / `db:seed` (or set `SEED_INSTRUCTOR_PASSWORD`).
3. Optional: log in as **student** (`student@example.com`) to see the read-only learner view.

Useful seeded courses (from `db/seeds.rb`):

| Course slug | Example lesson |
|---|---|
| `intro-to-ruby` | "What is Ruby?" |
| `linear-algebra-foundations` | "Vectors" |

Test/fixture course (if you use `bin/rails test` data): `algebra` → lesson "Intro to Algebra".

---

### 2.3 Pages to visit — checklist

Work through these in order. Compare **what you see** (current) with **what we want** (goal).

#### A. Lesson show — student / guest view (read)

| | |
|---|---|
| **URL** | `/courses/intro-to-ruby/lessons/1` (or click any lesson from the course page) |
| **Login** | None, or student |
| **Current** | Lesson description is plain text. Line breaks may show as paragraphs via `simple_format`, but there is **no** rich formatting (bold, lists, links styled as rich HTML). |
| **Goal** | Same area renders **HTML from ActionText** — bold, lists, links, inline images if the instructor added them. Wrapped in `.prose` like materials. |
| **File** | `app/views/lessons/show.html.haml` (line ~29–30) |

**What to look for:** Scroll below the video/title. The block starting with "Ruby is a dynamic, object-oriented…" is the **lesson body**.

---

#### B. Lesson edit — instructor view (write) — **main page for this PR**

| | |
|---|---|
| **URL** | `/courses/intro-to-ruby/lessons/1/edit` |
| **Login** | Instructor (or admin) |
| **Current** | **"Lesson description"** is a large **monospace plain textarea** — no toolbar, no bold button, feels like editing raw text. |
| **Goal** | **Trix editor** with toolbar (bold, italic, lists, link, attach file…) plus optional **"Insert HTML"** button — same pattern as lesson materials. |
| **File** | `app/views/lessons/_form.html.haml` (line ~14–15) |

**What to look for:** Expand **"Lesson details"** at the bottom of the edit page. The field labelled "Lesson description" is what we are replacing.

This is the **most important page** to understand before implementing.

---

#### C. Lesson material — rich text (reference / “already done”)

| | |
|---|---|
| **URL** | `/courses/intro-to-ruby/lessons/1/edit` → **Materials** → **+ Add material** → choose kind **"Rich text (Trix editor)"** |
| **Or** | Edit an existing HTML material if one exists |
| **Login** | Instructor |
| **Current** | Full **Trix** editor with toolbar and "Insert HTML". This is the **target UX** for lesson body. |
| **Goal** | Unchanged — use this page as the **design reference** when building lesson body. |
| **Files** | `app/views/lesson_materials/_form.html.haml`, `app/javascript/controllers/trix_insert_html_controller.js` |

**What to look for:** Notice toolbar, styling, dark mode (if enabled), and how content looks when saved.

---

#### D. Lesson material — show (read)

| | |
|---|---|
| **URL** | Open a lesson that has a **Rich text** material, e.g. lesson show → Materials section |
| **Login** | Any |
| **Current** | Material content renders as formatted HTML inside `.prose.max-w-none`. |
| **Goal** | Lesson **body** on the same page should render the same way after the PR. |
| **File** | `app/views/lesson_materials/_material.html.haml` (line ~29) |

**What to look for:** Compare material HTML rendering with lesson body rendering — today they behave differently; after the PR they should match.

---

#### E. Course page — lesson cards (secondary)

| | |
|---|---|
| **URL** | `/courses/intro-to-ruby` |
| **Login** | Any |
| **Current** | Each lesson card may show a **2-line preview** of `lesson.body` as plain text. |
| **Goal** | Preview should show **plain text extracted from ActionText** (no raw HTML tags in the card). May need a small code change in `_card.html.haml`. |
| **File** | `app/views/lessons/_card.html.haml` (line ~37–38) |

**What to look for:** Small grey snippet under the lesson title on each card.

---

#### F. Pages that are **not** in scope (do not expect changes)

Visit these so you know they are **out of scope** for this PR:

| Page | URL (example) | Editor today | This PR |
|---|---|---|---|
| Course description | `/courses/intro-to-ruby/edit` | Plain textarea | No change |
| Subject description | `/admin/subjects/.../edit` | Plain textarea | No change |
| Site hero | `/admin/site_settings/edit` (Hero tab) | Textarea + Markdown/HTML mode | No change |
| Question prompt | `.../lessons/1/questions/new` | Plain textarea | No change |
| Lesson material — Raw HTML | Materials → kind "Raw HTML" | Monospace textarea | No change |
| Lesson material — PDF / audio | Materials → other kinds | File upload / URL | No change |

---

### 2.4 Side-by-side: lesson body vs lesson material

| | Lesson body (today) | Lesson material — Rich text (today) |
|---|---|---|
| **Where stored** | `lessons.body` database column (plain text) | `action_text_rich_texts` table (HTML) |
| **Model** | `Lesson` — no `has_rich_text` | `LessonMaterial` — `has_rich_text :body` |
| **Edit UI** | Monospace `text_area` | Trix `rich_text_area` + Insert HTML |
| **Show UI** | `simple_format(@lesson.body)` | `@material.body` in `.prose` |
| **After PR** | Same stack as material column → | Same (unchanged) |

---

### 2.5 Where data lives (for DB checks)

If you want to verify in the console (`bin/rails console`):

```ruby
# Lesson body TODAY — plain string on the row
Lesson.first.read_attribute(:body)
# => "Ruby is a dynamic, object-oriented..."

# Lesson material rich text TODAY — ActionText
LessonMaterial.find_by(kind: :html)&.body&.to_s

# After migration — lesson body should look like material:
Lesson.first.body.to_s   # ActionText object, HTML inside
```

Tables involved:

| Table | Purpose |
|---|---|
| `lessons` | Has `body` text column **today** — column removed after migration |
| `action_text_rich_texts` | Stores rich HTML per record (`Lesson`, `LessonMaterial`, …) |
| `active_storage_blobs` / `attachments` | Inline images pasted into Trix |

---

### 2.6 Suggested 15-minute walkthrough

1. **Guest view** — Open `/courses/intro-to-ruby/lessons/1`. Note plain lesson description.
2. **Instructor edit** — Open `.../edit`. Note plain textarea for "Lesson description".
3. **Reference UI** — Add material → Rich text (Trix). Type bold text, save, view on lesson page.
4. **Compare** — Material looks rich; lesson body still looks plain. **That gap is what this PR closes.**
5. **Optional** — Toggle dark mode (site theme). Trix on materials should look fine; lesson textarea has no toolbar to worry about yet.

When you can explain step 4 to a colleague, you are ready to implement.

---

## 3. Current state (codebase audit)

ActionText infrastructure is **already present**. Lesson materials already use Trix. The main gap is the **lesson body** field, which still uses a plain `text` column and `simple_format` rendering.

### Already implemented

| Area | Status | Location |
|---|---|---|
| ActionText tables | ✅ Migrated | `action_text_rich_texts`, `active_storage_*` |
| Trix JS import | ✅ | `config/importmap.rb`, `app/javascript/application.js` |
| Trix / ActionText CSS | ✅ incl. dark mode | `app/assets/stylesheets/actiontext.css` |
| Lesson material rich text | ✅ `has_rich_text :body` | `app/models/lesson_material.rb` |
| Material form (Trix editor) | ✅ `rich_text_area` + Insert HTML helper | `app/views/lesson_materials/_form.html.haml` |
| Material display | ✅ `.prose` + `material.body` | `app/views/lesson_materials/_material.html.haml` |
| Stimulus: Insert HTML panel | ✅ | `app/javascript/controllers/trix_insert_html_controller.js` |
| Content partial wrapper | ✅ | `app/views/layouts/action_text/contents/_content.html.erb` |

### Not yet on ActionText

| Area | Current approach | Notes |
|---|---|---|
| **Lesson body** | `lessons.body` text column + `text_area` + `simple_format` | Primary target for this PR |
| Course description | `courses.description` text column + `text_area` + `simple_format` | Optional follow-up |
| Subject description | `subjects.description` text column + `text_area` | Optional follow-up |
| Site hero content | `site_settings.hero_content` + Markdown/HTML/plain modes via Redcarpet | Keep as-is for now (different use case) |
| Question prompts | Plain `text_area` | Keep as plain text (not rich content) |
| Rating comments | Plain `text_area` | Keep as plain text |

### Documentation drift

`README.md` states *"Full course and lesson authoring with rich-text body (ActionText)"* but `Lesson` does not declare `has_rich_text :body` and the edit form uses a monospace `text_area`. This PR should align code with documentation.

---

## 4. Scope

### In scope (this PR)

1. Migrate **Lesson#body** from `lessons.body` text column to ActionText (`has_rich_text :body`).
2. Replace the lesson form `text_area` with `rich_text_area`.
3. Update lesson show (and any other render sites) to output ActionText HTML safely.
4. Data migration: copy existing plain-text lesson bodies into `action_text_rich_texts`.
5. Reuse existing Trix styling and optionally the **Insert HTML** Stimulus controller on the lesson form.
6. Update tests, fixtures, and seeds.
7. Remove the obsolete `lessons.body` column after migration (or in a follow-up migration once verified).
8. Update README if any wording still implies CKEditor or misstates current behaviour.

### Out of scope (defer)

- Course / subject descriptions → ActionText (separate PR if needed).
- Replacing `raw_html` lesson material kind (power users may still want unsanitised HTML paste).
- Hero content format changes (Markdown remains appropriate for landing-page copy).
- CKEditor removal (not present in repo today).
- Advanced Trix toolbar plugins (e.g. @mentions, custom blocks) unless required immediately.

---

## 5. Implementation plan

### Phase 1 — Model & migration

```ruby
# app/models/lesson.rb
has_rich_text :body
```

**Migration strategy (recommended):**

1. Add `has_rich_text :body` while the `lessons.body` column still exists.
2. Run a data migration (Rake task or reversible migration) that, for each lesson with a non-blank `lessons.body`:
   - Creates an `ActionText::RichText` record (`name: "body"`, `record: lesson`).
   - Wraps plain text in `<div>` / converts newlines to `<br>` or `<p>` tags so Trix can edit it cleanly.
3. Verify counts: `Lesson.where.not(body: [nil, ""]).count` == `ActionText::RichText.where(record_type: "Lesson", name: "body").count`.
4. Remove `lessons.body` column in a second migration once QA passes.

**Plain-text → HTML conversion rule:**

```ruby
# Pseudocode — prefer simple paragraphs over raw newlines
def plain_text_to_action_text(html_escaped_text)
  paragraphs = html_escaped_text.to_s.split(/\r?\n\r?\n/)
  paragraphs.map { |p| "<p>#{ERB::Util.html_escape(p).gsub("\n", "<br>")}</p>" }.join
end
```

Keep the old column read-only during transition; do not dual-write indefinitely.

### Phase 2 — Forms & views

| File | Change |
|---|---|
| `app/views/lessons/_form.html.haml` | Replace `f.text_area :body` with `f.rich_text_area :body` inside a `trix-insert-html` wrapper (mirror lesson materials form) |
| `app/views/lessons/show.html.haml` | Replace `simple_format(@lesson.body)` with `.prose.max-w-none.trix-content= @lesson.body` |
| `app/controllers/lessons_controller.rb` | Strong params already permit `:body` — no change expected |
| `app/services/lesson_form_assignment_service.rb` | Confirm `:body` still flows through assignment |

**Display pattern (match lesson materials):**

```haml
.prose.max-w-none= @lesson.body
```

ActionText content is sanitised on save; do not call `.html_safe` on the output.

### Phase 3 — Trix customisation (Rails guide)

Follow [Customizing the rich text content editor (Trix)](https://guides.rubyonrails.org/action_text_overview.html#customizing-the-rich-text-content-editor-trix):

1. **Toolbar** — If we need extra buttons (e.g. Insert HTML is already a custom Stimulus panel), register Trix config in a dedicated JS file pinned via importmap, e.g. `app/javascript/trix_config.js`, imported after Trix in `application.js`.
2. **Attachments** — ActionText uses ActiveStorage. Confirm `config.active_storage.service` is set for dev/test/prod. Lesson body images will store in the same blob table as other uploads.
3. **CSS** — Extend `actiontext.css` for Tailwind `.prose` compatibility inside `.trix-content` if headings/lists look off.
4. **Dark mode** — Reuse existing `html.theme-dark trix-*` rules; extend if lesson form toolbar differs from materials form.

**Reuse existing Insert HTML controller** rather than building a CKEditor-style source mode:

- `app/javascript/controllers/trix_insert_html_controller.js` already documents that unsupported HTML is dropped when inserted — acceptable trade-off vs CKEditor's full HTML mode.

### Phase 4 — Tests & fixtures

| File | Change |
|---|---|
| `test/fixtures/lessons.yml` | Move body content to ActionText fixtures or create in `setup` blocks |
| `test/controllers/lessons_controller_test.rb` | POST/PATCH with ActionText body param format if needed |
| `test/models/lesson_test.rb` | Assert `lesson.body.present?` via ActionText |
| `test/controllers/lesson_materials_controller_test.rb` | Already covers ActionText for materials — use as reference |
| New: `test/tasks/migrate_lesson_bodies_test.rb` or migration test | Verify plain-text → rich text conversion |

**ActionText in tests:** Setting `lesson.body = "<p>Hello</p>"` works on models with `has_rich_text`. Fixtures for ActionText require `action_text_rich_texts` entries or factory-style setup in tests.

### Phase 5 — Seeds & docs

- `db/seeds.rb` — Seeds already set `body:` on lessons; update to use ActionText after model change.
- `README.md` — Correct any remaining inaccuracies; add a short "Rich text editing" note pointing to Trix + MIT licence.
- This planning doc — Mark sections complete as implemented.

---

## 6. File checklist (PR)

```
app/models/lesson.rb                          # has_rich_text :body
db/migrate/TIMESTAMP_migrate_lesson_body_to_action_text.rb
db/migrate/TIMESTAMP_remove_body_from_lessons.rb          # after QA
app/views/lessons/_form.html.haml             # rich_text_area
app/views/lessons/show.html.haml              # ActionText render
app/javascript/application.js                 # trix_config import (if needed)
app/assets/stylesheets/actiontext.css         # prose tweaks (if needed)
db/seeds.rb
test/fixtures/lessons.yml
test/controllers/lessons_controller_test.rb
test/models/lesson_test.rb
lib/tasks/action_text.rake                    # optional data migration task
README.md
docs/planning/actiontext-trix-editor.md       # update status → Done
```

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Existing lesson bodies lost on migration | Reversible migration; backup `lessons.body` before drop; run on staging first |
| Plain text with special HTML chars breaks display | Use `ERB::Util.html_escape` during conversion |
| Instructors expect full HTML source editing | Keep `raw_html` lesson material kind; offer Insert HTML on Trix (already built) |
| Inline images in lesson body increase storage | Document ActiveStorage limits; reuse existing validation patterns |
| Turbo navigation re-initialises Trix oddly | Lesson materials form already works — copy patterns; test edit → save → edit |
| Trix feature set smaller than CKEditor | Accept for v1; tables/complex layouts belong in lesson materials or PDFs |

---

## 8. Why not CKEditor (reference for PR description)

For reviewers and future contributors:

1. **Licence** — CKEditor 5 is GPL-2+ with commercial terms for many deployments; it is not MIT. AI LMS is MIT-licensed ([LICENSE](../LICENSE)).
2. **Operational cost** — Self-hosted CKEditor builds, licence keys, and feature gating (freemium model) add friction compared to Trix bundled via Rails.
3. **Duplication** — We already invested in Trix for lesson materials (dark theme, Insert HTML, ActionStorage). One editor stack reduces maintenance.
4. **Rails conventions** — ActionText handles sanitisation, attachments, and rendering consistently across the app.

---

## 9. Test plan (manual QA)

- [ ] Create a new lesson with bold, lists, and a link in the body; save and view on lesson show page.
- [ ] Upload an inline image in lesson body; confirm ActiveStorage blob and display.
- [ ] Edit an existing seeded lesson; confirm migrated plain-text body appears in Trix.
- [ ] Toggle dark mode; confirm Trix toolbar and content remain readable.
- [ ] Use Insert HTML on lesson form; confirm partial HTML converts sensibly.
- [ ] Run `bin/rails test` — all green.
- [ ] Run data migration on a DB copy; spot-check 5+ lessons before dropping column.

---

## 10. Suggested PR title & description

**Title:** Adopt ActionText + Trix for lesson body rich text editing

**Description bullets:**

- Migrate `Lesson#body` from plain text column to ActionText (`has_rich_text`)
- Replace lesson form textarea with Trix `rich_text_area` (consistent with lesson materials)
- Data migration for existing lesson content
- Align README with actual editor stack; document MIT-licensed Trix choice over CKEditor

---

## 11. Timeline estimate

| Phase | Effort |
|---|---|
| Model + data migration | 2–3 hours |
| Forms, views, styling | 1–2 hours |
| Tests + seeds | 2–3 hours |
| Manual QA + README | 1 hour |
| **Total** | **~1 day** |

---

## 12. Open questions

1. **Drop `lessons.body` in same PR or follow-up?** — Recommend follow-up migration after staging verification to keep rollback easy.
2. **Course description next?** — Product decision; not blocking this PR.
3. **Insert HTML on lesson form by default?** — Recommend yes (parity with lesson materials form).
4. **Attachment size / type limits on lesson body embeds?** — Confirm whether to add `active_storage_validations` on rich-text attachments globally or per-model.

---

## References

- [Rails Action Text overview](https://guides.rubyonrails.org/action_text_overview.html)
- [Customizing Trix (Rails guide)](https://guides.rubyonrails.org/action_text_overview.html#customizing-the-rich-text-content-editor-trix)
- [Trix — MIT licence](https://github.com/basecamp/trix)
- [CKEditor 5 licence](https://github.com/ckeditor/ckeditor5/blob/master/packages/ckeditor5/LICENSE.md)
