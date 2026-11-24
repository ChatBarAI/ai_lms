module LearningReportsHelper
  # Shared Tailwind classes for the module and lesson report pages.
  def report_card_class = "bg-white border border-gray-300 rounded-lg shadow-sm"
  def report_card_heading_class = "px-5 py-3 border-b border-gray-200 text-base font-semibold text-gray-900"
  def report_th_class = "px-4 py-2 text-xs font-semibold uppercase tracking-wide text-gray-600"
  def report_empty_class = "px-5 py-4 text-sm text-gray-600"

  def admin_report_context?
    controller_path.start_with?("admin/")
  end

  def learning_course_report_path(course)
    admin_report_context? ? report_admin_course_path(course) : report_course_path(course)
  end

  def learning_lesson_report_path(course, lesson, **options)
    admin_report_context? ? report_admin_course_lesson_path(course, lesson, **options) : report_course_lesson_path(course, lesson, **options)
  end

  def learning_question_report_path(course, lesson, question, **query)
    if admin_report_context?
      question_report_admin_course_lesson_path(course, lesson, question, **query)
    else
      question_report_course_lesson_path(course, lesson, question, **query)
    end
  end

  def learning_marking_queue_path(**query)
    admin_report_context? ? admin_marking_queue_path(**query) : marking_queue_path(**query)
  end

  def learning_answer_score_path(answer)
    return admin_question_answer_score_path(answer) if admin_report_context?

    lesson = answer.question.lesson
    course_lesson_question_answer_score_path(lesson.course, lesson, answer)
  end

  def learning_report_user(user)
    return user.email unless admin_report_context?

    link_to user.email, admin_user_path(user), class: "text-indigo-600 hover:underline"
  end
end
