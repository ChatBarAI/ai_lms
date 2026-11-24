class AddPendingIndexToQuestionAnswers < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  # Pending (unscored) answers are counted on every instructor page load (nav
  # badge, home alert, marking queue). A partial index keeps that lookup small
  # however many scored answers accumulate.
  def change
    add_index :question_answers, :question_id,
              where: "ai_score IS NULL",
              name: "index_question_answers_pending_on_question_id",
              algorithm: :concurrently
  end
end
