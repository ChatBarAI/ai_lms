class Ability
  include CanCan::Ability

  def initialize(user)
    alias_action :certificate_layout, :update_certificate_layout, to: :update
    alias_action :publish, :unpublish, to: :update

    allow_guest_catalog_access if SiteSetting.current.allow_guest_access?

    return if user.blank?

    if user.admin?
      can :manage, :all
      return
    end

    allow_authenticated_catalog_access(user)
    allow_student_capabilities(user)
    allow_instructor_capabilities(user) if user.instructor?
  end

  private

  def allow_guest_catalog_access
    can :read, Subject
    can :read, Course, published_at: ..Time.current, public_access_enabled: true
    can :read, Lesson, published_at: ..Time.current, course: { published_at: ..Time.current, public_access_enabled: true }
    can :read, LessonMaterial, lesson: { published_at: ..Time.current, course: { published_at: ..Time.current, public_access_enabled: true } }
  end

  def allow_authenticated_catalog_access(user)
    # Signed-in users should always be able to browse published catalogue items,
    # even when guest access is disabled.
    can :read, Subject
    can :read, Course, published_at: ..Time.current

    # Authenticated users can read instructor-owned drafts they own.
    can :read, Lesson, published_at: ..Time.current, course: { published_at: ..Time.current }
    can :read, Lesson, course: { owner_id: user.id }
    can :read, Question, lesson: { published_at: ..Time.current, course: { published_at: ..Time.current } }
    can :read, Question, lesson: { course: { owner_id: user.id } }
    can :read, LessonMaterial, lesson: { published_at: ..Time.current, course: { published_at: ..Time.current } }
    can :read, LessonMaterial, lesson: { course: { owner_id: user.id } }
  end

  def allow_student_capabilities(user)
    can [ :create, :read, :update, :destroy ], Rating, user_id: user.id
    can :read, Enrollment, user_id: user.id
    can :create, Enrollment, user_id: user.id
    can :read, Progress, enrollment: { user_id: user.id }
    can :update, Progress, enrollment: { user_id: user.id }
    can [ :create, :read ], QuestionAnswer, enrollment: { user_id: user.id }
    can :create, LessonMaterialAcknowledgement, enrollment: { user_id: user.id }
    can :read, LessonMaterialAcknowledgement, enrollment: { user_id: user.id }
    can :read, Certificate, user_id: user.id
  end

  def allow_instructor_capabilities(user)
    can :create, Course
    can [ :read, :update, :destroy ], Course, owner_id: user.id
    can :manage, Lesson, course: { owner_id: user.id }
    can :manage, Question, lesson: { course: { owner_id: user.id } }
    can :manage, QuestionGenerationTask, lesson: { course: { owner_id: user.id } }
    can :manage, LessonMaterial, lesson: { course: { owner_id: user.id } }
    can :read, QuestionAnswer, question: { lesson: { course: { owner_id: user.id } } }
  end
end
