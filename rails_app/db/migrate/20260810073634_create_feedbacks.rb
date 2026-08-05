class CreateFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :feedbacks do |t|
      t.references :message, null: false, foreign_key: true, index: { unique: true }
      t.integer :rating, null: false

      t.timestamps
    end

    add_check_constraint :feedbacks, "rating IN (-1, 1)", name: "feedbacks_rating_check"
  end
end
