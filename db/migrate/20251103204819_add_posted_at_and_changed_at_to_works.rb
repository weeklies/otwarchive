class AddPostedAtAndChangedAtToWorks < ActiveRecord::Migration[7.2]
  uses_departure! if Rails.env.staging? || Rails.env.production?

  def change
    change_table :works, bulk: true do |t|
      t.column :posted_at, :datetime
      t.column :changed_at, :datetime
    end
  end
end
