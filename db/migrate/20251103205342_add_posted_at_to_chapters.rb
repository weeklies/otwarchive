class AddPostedAtToChapters < ActiveRecord::Migration[7.2]
  uses_departure! if Rails.env.staging? || Rails.env.production?

  def change
    add_column :chapters, :posted_at, :datetime
  end
end
