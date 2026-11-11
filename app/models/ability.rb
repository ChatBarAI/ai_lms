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
    can :read, Lesson, published_at: ..Time.current, course: { published_at: ..Time.current, public_access_enabled: true, access_policy: "free" }
    can :read, LessonMaterial, lesson: { published_at: ..Time.current, course: { published_at: ..Time.current, public_access_enabled: true, access_policy: "free" } }
  end

  def allow_authenticated_catalog_access(user)
    # Signed-in users should always be able to browse published catalogue items,
    # even when guest access is disabled.
    can :read, Subject
    can :read, Course, published_at: ..Time.current

    learning_course_conditions(user).each do |condition|
      published = condition.merge(published_at: ..Time.current)
      can :read, Lesson, published_at: ..Time.current, course: published
      can :read, Question, lesson: { published_at: ..Time.current, course: published }
      can :read, LessonMaterial, lesson: { published_at: ..Time.current, course: published }
    end
    can :read, Lesson, course: { owner_id: user.id }
    can :read, Question, lesson: { course: { owner_id: user.id } }
    can :read, LessonMaterial, lesson: { course: { owner_id: user.id } }
  end

  def learning_course_conditions(user)
    # Only this learner's effective course IDs; SQL scopes remain queryable and
    # CanCan's in-memory matcher receives arrays, not ActiveRecord relations.
    @learning_course_conditions ||= CourseAccess.conditions(user)
  end

  def allow_student_capabilities(user)
    can [ :create, :read, :update, :destroy ], Rating, user_id: user.id
    can [ :read, :create ], Enrollment, user_id: user.id
    can :read, Progress, enrollment: { user_id: user.id }
    can :read, QuestionAnswer, enrollment: { user_id: user.id }
    can :read, LessonMaterialAcknowledgement, enrollment: { user_id: user.id }
    learning_course_conditions(user).each do |condition|
      enrollment = { user_id: user.id, archived_at: nil, course: condition.merge(published_at: ..Time.current) }
      can :create, QuestionAnswer, enrollment: enrollment
      can :create, LessonMaterialAcknowledgement, enrollment: enrollment
    end
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
