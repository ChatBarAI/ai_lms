require "csv"

class Course < ApplicationRecord
  belongs_to :subject, optional: true
  belongs_to :owner, class_name: "User"

  has_many :lessons, -> { order(:position) }, dependent: :destroy
  has_many :enrollments, dependent: :destroy
  has_many :students, through: :enrollments, source: :user
  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  has_one_attached :cover_image
  has_one_attached :certificate_template

  validates :cover_image, content_type: %w[image/png image/jpeg image/webp],
                          size: { less_than: 5.megabytes }
  validates :certificate_template, content_type: %w[image/png image/jpeg],
                                   size: { less_than: 10.megabytes }

  validates :title, presence: true
  validates :locale, presence: true, inclusion: { in: User::SUPPORTED_LOCALES.keys }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/ }

  before_validation :assign_slug, on: :create

  scope :published, -> { where(published_at: ..Time.current) }
  scope :visible_to, ->(user) {
    locales = user&.course_locales.presence
    locales.present? ? where(locale: locales) : all
  }

  def self.ransackable_attributes(_auth = nil)
    %w[title slug description locale owner_id subject_id published_at created_at updated_at id]
  end

  def self.ransackable_associations(_auth = nil)
    %w[subject owner lessons enrollments tags]
  end

  CERTIFICATE_FIELDS = %w[name course_title date certificate_no].freeze

  ADMIN_CSV_HEADERS = %w[
    id
    slug
    title
    locale
    subject
    owner_email
    status
    published_at
    created_at
    updated_at
    total_lessons
    published_lessons
    enrollments
    active_learners
    completed_progresses
    in_progress_progresses
    not_started_progresses
    total_progress_records
    avg_score
    avg_rating
    ratings_count
    certificates_issued
    last_enrollment_at
    last_completion_at
  ].freeze

  # x / y are percentages (0..100) of page width/height, anchored at the
  # centre of the rendered text. Origin is top-left.
  DEFAULT_CERTIFICATE_LAYOUT = {
    "name"           => { "x" => 50,   "y" => 46,   "size" => 32, "align" => "center", "bold" => true },
    "course_title"   => { "x" => 50,   "y" => 59.5, "size" => 22, "align" => "center", "bold" => true },
    "date"           => { "x" => 23,   "y" => 89,   "size" => 12, "align" => "center", "bold" => false },
    "certificate_no" => { "x" => 50,   "y" => 90,   "size" => 9,  "align" => "center", "bold" => false }
  }.freeze

  def certificate_layout_with_defaults
    stored = (certificate_layout || {}).deep_stringify_keys
    CERTIFICATE_FIELDS.each_with_object({}) do |key, h|
      defaults = DEFAULT_CERTIFICATE_LAYOUT[key]
      h[key] = defaults.merge(stored[key] || {})
    end
  end

  def published?
    published_at.present? && published_at <= Time.current
  end

  def to_param
    slug.presence || id.to_s
  end

  def progresses
    Progress.where(enrollment_id: enrollments.select(:id))
  end

  def enrollment_count
    enrollments.count
  end

  def active_learners_count
    enrollments.active.count
  end

  def completion_rate
    total = enrollments.count
    return 0 if total.zero?
    done = enrollments.select(&:fully_completed?).size
    ((done.to_f / total) * 100).round(1)
  end

  def average_score
    progresses.where.not(score: nil).average(:score)&.round(1)
  end

  def average_rating
    Rating.where(lesson_id: lessons.select(:id)).average(:stars)&.round(2)
  end

  def self.admin_csv_scope(subject_id: nil)
    scope = all
    scope = scope.where(subject_id:) if subject_id.present?

    scope
      .joins("LEFT JOIN subjects ON subjects.id = courses.subject_id")
      .joins("LEFT JOIN users owners ON owners.id = courses.owner_id")
      .joins(lesson_stats_join_sql)
      .joins(enrollment_stats_join_sql)
      .joins(progress_stats_join_sql)
      .joins(rating_stats_join_sql)
      .joins(certificate_stats_join_sql)
      .select(export_select_clause)
      .order(created_at: :desc)
  end

  def self.to_admin_csv(scope)
    CSV.generate do |out|
      out << ADMIN_CSV_HEADERS
      scope.find_each do |course|
        out << csv_export_row(course)
      end
    end
  end

  def self.admin_csv_filename(brand_name:)
    slug = brand_name.to_s.strip
    brand_slug = slug.present? ? slug.parameterize(separator: "-") : "lms"
    "#{brand_slug}-courses-#{Date.current}.csv"
  end

  private

  def self.csv_export_row(course)
    [
      course.id,
      course.slug,
      course.title,
      course.locale,
      course.subject_name,
      course.owner_email,
      course.published? ? "published" : "draft",
      course.published_at&.iso8601,
      course.created_at&.iso8601,
      course.updated_at&.iso8601,
      course.total_lessons_count.to_i,
      course.published_lessons_count.to_i,
      course.enrollments_count.to_i,
      course.active_learners_count.to_i,
      course.completed_progresses_count.to_i,
      course.in_progress_progresses_count.to_i,
      course.not_started_progresses_count.to_i,
      course.total_progress_records.to_i,
      course.avg_score&.to_f&.round(1),
      course.avg_rating&.to_f&.round(2),
      course.ratings_count.to_i,
      course.certificates_issued.to_i,
      course.last_enrollment_at&.iso8601,
      course.last_completion_at&.iso8601
    ]
  end

  def self.export_select_clause
    <<~SQL.squish
      courses.id,
      courses.slug,
      courses.title,
      courses.locale,
      courses.published_at,
      courses.created_at,
      courses.updated_at,
      subjects.name AS subject_name,
      owners.email AS owner_email,
      COALESCE(lesson_stats.total_lessons_count, 0) AS total_lessons_count,
      COALESCE(lesson_stats.published_lessons_count, 0) AS published_lessons_count,
      COALESCE(enrollment_stats.enrollments_count, 0) AS enrollments_count,
      COALESCE(enrollment_stats.last_enrollment_at, NULL) AS last_enrollment_at,
      COALESCE(progress_stats.active_learners_count, 0) AS active_learners_count,
      COALESCE(progress_stats.completed_progresses_count, 0) AS completed_progresses_count,
      COALESCE(progress_stats.in_progress_progresses_count, 0) AS in_progress_progresses_count,
      COALESCE(progress_stats.not_started_progresses_count, 0) AS not_started_progresses_count,
      COALESCE(progress_stats.total_progress_records, 0) AS total_progress_records,
      progress_stats.avg_score AS avg_score,
      progress_stats.last_completion_at AS last_completion_at,
      COALESCE(rating_stats.ratings_count, 0) AS ratings_count,
      rating_stats.avg_rating AS avg_rating,
      COALESCE(cert_stats.certificates_issued, 0) AS certificates_issued
    SQL
  end

  def self.lesson_stats_join_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT
          lessons.course_id AS course_id,
          COUNT(lessons.id) AS total_lessons_count,
          COUNT(*) FILTER (WHERE lessons.published_at IS NOT NULL AND lessons.published_at <= NOW()) AS published_lessons_count
        FROM lessons
        GROUP BY lessons.course_id
      ) lesson_stats ON lesson_stats.course_id = courses.id
    SQL
  end

  def self.enrollment_stats_join_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT
          enrollments.course_id AS course_id,
          COUNT(enrollments.id) AS enrollments_count,
          MAX(enrollments.enrolled_at) AS last_enrollment_at
        FROM enrollments
        GROUP BY enrollments.course_id
      ) enrollment_stats ON enrollment_stats.course_id = courses.id
    SQL
  end

  def self.progress_stats_join_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT
          enrollments.course_id AS course_id,
          COUNT(progresses.id) AS total_progress_records,
          COUNT(*) FILTER (WHERE progresses.status = #{Progress.statuses[:completed]}) AS completed_progresses_count,
          COUNT(*) FILTER (WHERE progresses.status = #{Progress.statuses[:in_progress]}) AS in_progress_progresses_count,
          COUNT(*) FILTER (WHERE progresses.status = #{Progress.statuses[:not_started]}) AS not_started_progresses_count,
          COUNT(DISTINCT enrollments.id) FILTER (
            WHERE progresses.status IN (#{Progress.statuses[:in_progress]}, #{Progress.statuses[:completed]})
          ) AS active_learners_count,
          AVG(progresses.score) FILTER (WHERE progresses.score IS NOT NULL) AS avg_score,
          MAX(progresses.completed_at) AS last_completion_at
        FROM enrollments
        LEFT JOIN progresses ON progresses.enrollment_id = enrollments.id
        GROUP BY enrollments.course_id
      ) progress_stats ON progress_stats.course_id = courses.id
    SQL
  end

  def self.rating_stats_join_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT
          lessons.course_id AS course_id,
          COUNT(ratings.id) AS ratings_count,
          AVG(ratings.stars) FILTER (WHERE ratings.stars IS NOT NULL) AS avg_rating
        FROM lessons
        LEFT JOIN ratings ON ratings.lesson_id = lessons.id
        GROUP BY lessons.course_id
      ) rating_stats ON rating_stats.course_id = courses.id
    SQL
  end

  def self.certificate_stats_join_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT
          certificates.course_id AS course_id,
          COUNT(certificates.id) AS certificates_issued
        FROM certificates
        GROUP BY certificates.course_id
      ) cert_stats ON cert_stats.course_id = courses.id
    SQL
  end

  def assign_slug
    self.slug ||= title.to_s.parameterize
  end
end
