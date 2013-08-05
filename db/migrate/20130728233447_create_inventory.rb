class CreateInventory < ActiveRecord::Migration
  def up
     
    create_table :transactions do |t|
      t.float :dollars
    end
    
    # start with initial capital
    
    Transaction.create({:dollars => 300.00})
      
    # note we get an "id" column for free, thanks to ActiveRecord, and it is the primary key
    create_table :logs do |t|
      t.string :species
      t.boolean :consumed, :default => false
    end
    
    # create some initial logs
    #Log.create({:species => "Oak"})
    #Log.create({:species => "Beach"})
    #5.times do |i|
    #  Log.create({:species => "Ash"})
    #end

    
    create_table :blanks do |t|
      t.belongs_to :log
      t.float  :length
      t.boolean :consumed, :default => false
    end

    create_table :turnings do |t|
      t.belongs_to :blank
      t.string :league
      t.boolean :consumed, :default => false
    end
    
    create_table :bats do |t|
      t.belongs_to :turning
      t.string :model
      t.boolean :consumed, :default => false
    end
    
  
  end

  def down
    
    drop_table :transactions
    drop_table :logs
    drop_table :blanks
    drop_table :turnings
    drop_table :bats
    
  end
end
