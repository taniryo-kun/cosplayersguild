class CreateArticles < ActiveRecord::Migration
  def change
  	create_table :articles do |t|
  		t.string 	:title
  		t.text		:introduction
  		t.string 	:url
  		t.string 	:user
  		t.string	:tweet_id

  		t.timestamps
  	end
  	add_index :articles, :url
  end

end
