# Idempotent dev seeds. Run with: bin/rails db:seed
seed_password_sources = {}

resolve_seed_password = lambda do |env_key, label|
  value = ENV[env_key].to_s
  if value.present?
    seed_password_sources[label] = :env
    value
  else
    generated = SecureRandom.base58(8)
    seed_password_sources[label] = :generated
    generated
  end
end

admin_email    = ENV.fetch("SEED_ADMIN_EMAIL", "admin@example.com")
admin_name     = ENV.fetch("SEED_ADMIN_NAME",  "Admin")
admin_password = resolve_seed_password.call("SEED_ADMIN_PASSWORD", "admin")
instructor_password = resolve_seed_password.call("SEED_INSTRUCTOR_PASSWORD", "instructor")
student_password = resolve_seed_password.call("SEED_STUDENT_PASSWORD", "student")

puts "Seeding users..."
admin = User.find_or_initialize_by(email: admin_email)
admin.assign_attributes(name: admin_name, role: :admin, password: admin_password)
admin.save!

instructor = User.find_or_initialize_by(email: "instructor@example.com")
instructor.assign_attributes(name: "Ivy Instructor", role: :instructor, password: instructor_password)
instructor.save!

student = User.find_or_initialize_by(email: "student@example.com")
student.assign_attributes(name: "Sam Student", role: :student, password: student_password)
student.save!

puts "Seeding site settings..."
site = SiteSetting.current
site.brand_name = ENV["SEED_BRAND_NAME"] if ENV["SEED_BRAND_NAME"].present?
site.app_url    = ENV["SEED_APP_URL"]    if ENV["SEED_APP_URL"].present?
site.save!

puts "Seeding subjects..."
maths = Subject.find_or_create_by!(slug: "mathematics") do |s|
  s.name = "Mathematics"
  s.description = "Numbers, geometry, algebra, calculus."
end
prog = Subject.find_or_create_by!(slug: "programming") do |s|
  s.name = "Programming"
  s.description = "Software engineering and computer science."
end
Subject.find_or_create_by!(slug: "science") do |s|
  s.name = "Science"
  s.description = "Physics, chemistry, biology, earth science."
end

puts "Seeding courses + lessons..."
course = Course.find_or_initialize_by(slug: "intro-to-ruby")
course.assign_attributes(title: "Introduction to Ruby",
  description: "A beginner-friendly tour of the Ruby programming language. Covers syntax, blocks, classes, and idiomatic style.",
  subject: prog, owner: instructor, published_at: 1.day.ago)
course.save!

[
  { title: "What is Ruby?", body: "Ruby is a dynamic, object-oriented programming language created by Yukihiro 'Matz' Matsumoto in the mid-1990s. It emphasises programmer happiness and readable code." },
  { title: "Variables and basic types", body: "Ruby has Integers, Floats, Strings, Symbols, Arrays, and Hashes as its core data types. Everything in Ruby is an object, including numbers and nil." },
  { title: "Methods and blocks", body: "Methods are defined with def. Blocks are anonymous chunks of code passed to methods using do/end or { }. Blocks are central to idiomatic Ruby." }
].each_with_index do |attrs, idx|
  lesson = Lesson.find_or_initialize_by(course_id: course.id, position: idx + 1)
  lesson.assign_attributes(title: attrs[:title], body: attrs[:body], published_at: 1.day.ago)
  lesson.save!
end

algebra = Course.find_or_initialize_by(slug: "linear-algebra-foundations")
algebra.assign_attributes(title: "Linear Algebra: Foundations",
  description: "Vectors, matrices, and linear transformations -- the maths behind machine learning and graphics.",
  subject: maths, owner: instructor, published_at: 3.days.ago)
algebra.save!

[
  { title: "Vectors", body: "A vector is an ordered list of numbers representing magnitude and direction." },
  { title: "Matrices", body: "A matrix is a rectangular array of numbers used to represent linear transformations." }
].each_with_index do |attrs, idx|
  lesson = Lesson.find_or_initialize_by(course_id: algebra.id, position: idx + 1)
  lesson.assign_attributes(attrs.merge(published_at: 3.days.ago))
  lesson.save!
end

puts "Seeding sample questions..."
first_lesson = course.lessons.find_by(position: 1)
[
  { prompt: "Who created Ruby?", kind: :multiple_choice, choices: [ "Guido van Rossum", "Yukihiro Matsumoto", "Larry Wall", "Linus Torvalds" ], correct: "Yukihiro Matsumoto", points: 1 },
  { prompt: "Ruby is a statically typed language.", kind: :true_false, choices: [], correct: "false", points: 1 },
  { prompt: "What does the 'Matz' nickname refer to?", kind: :free_text, choices: [], correct: "Yukihiro Matsumoto", points: 1 }
].each_with_index do |q, idx|
  question = Question.find_or_initialize_by(lesson_id: first_lesson.id, position: idx + 1)
  question.assign_attributes(prompt: q[:prompt], kind: q[:kind], correct_answer: q[:correct], points: q[:points])
  question.choices_list = q[:choices]
  question.save!
end

vectors_lesson = algebra.lessons.find_by(position: 1)
[
  { prompt: "Which of the following quantities is a vector?", choices: [ "Temperature", "Mass", "Velocity", "Energy" ], correct: "Velocity" },
  { prompt: "A vector has which two main properties?", choices: [ "Speed and time", "Magnitude and direction", "Length and width", "Force and energy" ], correct: "Magnitude and direction" },
  { prompt: "What is the magnitude of the vector ⟨3,4⟩?", choices: [ "5", "7", "12", "25" ], correct: "5" },
  { prompt: "Two vectors are perpendicular if their dot product is:", choices: [ "1", "Equal to their magnitudes", "0", "Negative" ], correct: "0" }
].each_with_index do |q, idx|
  question = Question.find_or_initialize_by(lesson_id: vectors_lesson.id, position: idx + 1)
  question.assign_attributes(prompt: q[:prompt], kind: :multiple_choice, correct_answer: q[:correct], points: 1)
  question.choices_list = q[:choices]
  question.save!
end

puts "Seeding enrollment + progress for student..."
enrollment = Enrollment.find_or_create_by!(user: student, course: course) { |e| e.role = :student }
Progress.find_or_create_by!(enrollment: enrollment, lesson: first_lesson) do |p|
  p.status = :completed
  p.score = 100
end

puts ""
puts "=" * 60
puts "  SEED COMPLETE — DEV ACCOUNTS"
puts "=" * 60
puts "  Role        Email                     Password"
puts "  ----------  ------------------------  --------"
puts "  admin       #{admin_email.ljust(24)}  #{admin_password}#{seed_password_sources.fetch("admin") == :generated ? "  (generated)" : "  (from env)"}"
puts "  instructor  instructor@example.com    #{instructor_password}#{seed_password_sources.fetch("instructor") == :generated ? "  (generated)" : "  (from env)"}"
puts "  student     student@example.com       #{student_password}#{seed_password_sources.fetch("student") == :generated ? "  (generated)" : "  (from env)"}"
puts "=" * 60
if seed_password_sources.value?(:generated)
  puts "  NOTE: Generated passwords are shown once only."
  puts "  Set SEED_ADMIN_PASSWORD / SEED_INSTRUCTOR_PASSWORD /"
  puts "  SEED_STUDENT_PASSWORD env vars for repeatable credentials."
  puts "=" * 60
end
puts ""
