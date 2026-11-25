# Locked lessons and modules share one "locked" dialog (shared/_locked_dialog).
# A locked link keeps its href, so without JavaScript the server's own gate
# still applies; with JavaScript, status-modal fills the dialog and opens it.
# The layout renders the dialog once whenever a page builds a locked link.
# Which lessons and modules are locked comes from LessonGating.
module LockedContentHelper
  LOCKED_DIALOG_ID = "locked-dialog".freeze

  def locked_dialog_needed?
    @locked_dialog_needed == true
  end

  # Why a lesson is locked, for the dialog and the redirect notice. The
  # blocker is an earlier Lesson or a prerequisite Course (see LessonGating).
  def locked_lesson_message(course, blocker)
    return locked_course_message(missing_prerequisites_for_viewer(course)) if blocker.is_a?(Course)

    t("locked.lesson_message", title: blocker.title, **terms)
  end

  # Empty when the lesson is open (blocker is nil). A lesson locked by its
  # module's prerequisites opens the module dialog, with "View module" when
  # the page is not already that module.
  def locked_lesson_link_attributes(course, blocker)
    return {} unless blocker
    if blocker.is_a?(Course)
      return locked_course_link_attributes(missing_prerequisites_for_viewer(course),
                                           view_url: (course_path(course) unless @course == course))
    end

    locked_link_attributes(
      title: t("locked.lesson_title", lesson: terms[:lesson]),
      message: locked_lesson_message(course, blocker),
      url: course_lesson_path(course, blocker),
      link_label: t("locked.go_to", title: blocker.title)
    )
  end

  # Empty when the viewer may enrol (missing is empty). view_url adds a
  # "View module" button; trigger: "submit" suits a form (button_to), so the
  # dialog opens instead of submitting it. Guests cannot complete a
  # prerequisite, so their dialog offers "Sign in" instead of the prerequisite.
  def locked_course_link_attributes(missing, view_url: nil, trigger: "click")
    return {} if missing.empty?

    url, link_label =
      if user_signed_in?
        [ course_path(missing.first), t("locked.go_to", title: missing.first.title) ]
      else
        [ new_user_session_path, t("locked.sign_in") ]
      end
    attributes = locked_link_attributes(
      title: t("locked.course_title", course: terms[:course]),
      message: locked_course_message(missing),
      url: url,
      link_label: link_label,
      trigger: trigger
    )
    if view_url
      attributes[:data][:status_modal_secondary_url_param] = view_url
      attributes[:data][:status_modal_secondary_label_param] = t("locked.view_course", **terms)
    end
    attributes
  end

  # button_to handles submit events on the form and ARIA on the button.
  def locked_button_to_options(missing, form_data: {})
    lock = locked_course_link_attributes(missing, trigger: "submit")

    {
      form: { data: form_data.merge(lock.fetch(:data, {})) },
      aria: {
        haspopup: lock[:"aria-haspopup"],
        controls: lock[:"aria-controls"]
      }
    }
  end

  private

  def locked_course_message(missing)
    titles = missing.map { |prerequisite| t("locked.quoted", title: prerequisite.title) }.to_sentence
    key = user_signed_in? ? "locked.course_message" : "locked.course_message_guest"
    t(key, titles: titles, **terms)
  end

  def locked_link_attributes(title:, message:, url:, link_label:, trigger: "click")
    @locked_dialog_needed = true
    {
      "aria-haspopup": "dialog",
      "aria-controls": LOCKED_DIALOG_ID,
      data: {
        controller: "status-modal",
        action: "#{trigger}->status-modal#open",
        status_modal_dialog_id_value: LOCKED_DIALOG_ID,
        status_modal_title_param: title,
        status_modal_message_param: message,
        status_modal_link_url_param: url,
        status_modal_link_label_param: link_label
      }
    }
  end
end
