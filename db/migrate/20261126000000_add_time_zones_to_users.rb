class AddTimeZonesToUsers < ActiveRecord::Migration[7.2]
  def change
    # nil means follow the browser; retain its latest zone for emails/jobs.
    add_column :users, :time_zone, :string
    add_column :users, :browser_time_zone, :string
  end
end
