# Enrolment Gating — Tester Guide

**What you are testing:** Can an instructor lock an advanced course behind a beginner course?  
**App URL (local):** `http://localhost:3001` (use your host if different)  
**PDF with screenshots:** [`enrolment-gating-guide.pdf`](enrolment-gating-guide.pdf)

This guide is for **testers**, not developers. Follow Section 1, then Section 2.

---

## In one sentence

An instructor picks courses that must be finished first (“milestones”). A student who has **not** finished those milestones can still **see** the advanced course, but cannot **enrol** until every milestone is complete.

```
Instructor sets milestones → Student sees “Requires …” → Student finishes milestone → Student can enrol
```

---

## Accounts

| Who | Email | Password | Use for |
|-----|-------|----------|---------|
| Instructor | `instructor@example.com` | `student123` | Section 1 |
| Student | `student-prereq-a@example.com` | `student123` | Section 2 |
| Admin (optional) | `admin@example.com` | `student123` | Appendix |

## Courses

| Role | Course | URL |
|------|--------|-----|
| Milestone (finish first) | Introduction to Ruby | `/courses/intro-to-ruby` |
| Advanced (locked) | Linear Algebra: Foundations | `/courses/linear-algebra-foundations` |

---

## Section 1 — Login as Instructor

**Goal:** Configure Linear Algebra so students must complete Introduction to Ruby first.

### Step 1.1 — Sign in

1. Open `/users/sign_in`
2. Email: `instructor@example.com`
3. Password: `student123`
4. Click Sign in

### Step 1.2 — Open the advanced course

1. Go to Courses, or open `/courses/linear-algebra-foundations`
2. Confirm you see **Linear Algebra: Foundations**
3. Click **Edit**

### Step 1.3 — Set the milestone

1. Scroll to **Complete these courses first (milestones)**
2. Tick **Introduction to Ruby**
3. Click **Update Course**

**Done looks like:** Introduction to Ruby stays checked after save.

**Tip:** You can tick more than one milestone. The student must finish **all** of them.

### Instructor checklist

| # | Check | Pass? |
|---|--------|-------|
| 1 | Can open course edit as instructor | ☐ |
| 2 | Milestone checkboxes visible | ☐ |
| 3 | Introduction to Ruby saves as selected | ☐ |

---

## Section 2 — Login as Student

**Goal:** Confirm a student without the milestone cannot enrol, can still see the course, and knows which course to finish first.

**Before you start:** Sign out of the instructor account (or use a private window).

### Step 2.1 — Sign in as a blocked student

1. Open `/users/sign_in`
2. Email: `student-prereq-a@example.com`
3. Password: `student123`
4. Click Sign in

This account has **no enrolments** yet — good for seeing the lock.

### Step 2.2 — Open the catalogue

1. Go to `/courses`
2. Find **Linear Algebra: Foundations**

**Expect:** Course is still listed. Orange text: **Requires: Introduction to Ruby**

### Step 2.3 — Try to enrol in the advanced course

1. Open `/courses/linear-algebra-foundations`
2. Read the yellow box **Complete these courses first**
3. Confirm enrol is blocked

**Expect:** Link to Introduction to Ruby. Enrol not available yet.

### Step 2.4 — Open the milestone course (allowed)

1. Open `/courses/intro-to-ruby`
2. Confirm there is **no** milestone lock
3. Enrol and complete **all** lessons if you want to test unlock

**Unlock rule:** After every lesson in Introduction to Ruby is completed, return to Linear Algebra — Enrol should work.

### Student checklist

| # | Check | Pass? |
|---|--------|-------|
| 1 | Catalogue shows Requires: Introduction to Ruby | ☐ |
| 2 | Linear Algebra shows “Complete these courses first” | ☐ |
| 3 | Cannot enrol in Linear Algebra yet | ☐ |
| 4 | Can open / enrol in Introduction to Ruby | ☐ |
| 5 | (Optional) After finishing Ruby, enrol on Linear Algebra works | ☐ |

---

## Appendix — Admin force-enrol (optional)

**When:** An admin needs to put a student into a locked course without waiting for milestones.

1. Sign in as `admin@example.com` / `student123`
2. Admin → Users → `student-prereq-a@example.com`
3. **Force-enrol in course** → Linear Algebra: Foundations
4. Without **Skip prerequisite check** → should fail
5. With **Skip prerequisite check (force)** ticked → enrol succeeds

---

## Quick reference

| Situation | What the student sees |
|-----------|------------------------|
| No milestones on the course | Normal Enrol button |
| Milestones not finished | “Requires …” + locked enrol |
| All milestones finished | Normal Enrol button |
| Already enrolled before a milestone was added | Stays enrolled |

---

**PDF:** `docs/guides/enrolment-gating-guide.pdf` · Branch: `feat-enrolment-gating`
