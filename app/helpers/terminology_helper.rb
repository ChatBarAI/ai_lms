module TerminologyHelper
  # Returns a hash of terminology interpolations for use with `t(...)`.
  # Example:
  #   = t(".edit", **terms)
  # where the locale entry is: "Edit %{lesson_l}".
  #
  # Title-case variants (%{lesson}, %{lessons}, %{course}, ...) come from
  # `Model.model_name.human` so changing `activerecord.models.lesson.one`
  # cascades through the whole UI. Lowercase variants are derived for use
  # mid-sentence.
  def terms
    @_terms ||= begin
      lesson_one    = Lesson.model_name.human(count: 1)
      lesson_other  = Lesson.model_name.human(count: 2)
      course_one    = Course.model_name.human(count: 1)
      course_other  = Course.model_name.human(count: 2)
      subject_one   = Subject.model_name.human(count: 1)
      subject_other = Subject.model_name.human(count: 2)
      quiz_one      = I18n.t("activerecord.models.quiz.one", default: "Quiz")
      quiz_other    = I18n.t("activerecord.models.quiz.other", default: "Quizzes")
      {
        lesson:     lesson_one,
        lessons:    lesson_other,
        lesson_l:   lesson_one.downcase,
        lessons_l:  lesson_other.downcase,
        course:     course_one,
        courses:    course_other,
        course_l:   course_one.downcase,
        courses_l:  course_other.downcase,
        subject:    subject_one,
        subjects:   subject_other,
        subject_l:  subject_one.downcase,
        subjects_l: subject_other.downcase,
        quiz:       quiz_one,
        quizzes:    quiz_other,
        quiz_l:     quiz_one.downcase,
        quizzes_l:  quiz_other.downcase
      }
    end
  end
end
