class MigrateLessonBodyToActionText < ActiveRecord::Migration[7.2]
  class MigrationLesson < ApplicationRecord
    self.table_name = "lessons"
  end

  def up
    MigrationLesson.where.not(body: [ nil, "" ]).find_each do |lesson|
      next if ActionText::RichText.exists?(record_type: "Lesson", record_id: lesson.id, name: "body")

      ActionText::RichText.create!(
        record_type: "Lesson",
        record_id: lesson.id,
        name: "body",
        body: plain_text_to_html(lesson.read_attribute(:body))
      )
    end

    remove_column :lessons, :body, :text
  end

  def down
    add_column :lessons, :body, :text

    ActionText::RichText.where(record_type: "Lesson", name: "body").find_each do |rich_text|
      MigrationLesson.where(id: rich_text.record_id).update_all(body: rich_text.body.to_plain_text)
      rich_text.destroy!
    end
  end

  private

  def plain_text_to_html(plain_text)
    text = plain_text.to_s
    return "" if text.blank?

    text.split(/\r?\n\r?\n+/).map do |paragraph|
      escaped = ERB::Util.html_escape(paragraph).gsub("\n", "<br>")
      "<p>#{escaped}</p>"
    end.join
  end
end
