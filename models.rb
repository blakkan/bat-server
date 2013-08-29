require 'sinatra'
require 'pg'
require 'active_record'
require 'sinatra/activerecord'
require 'haml'
require 'json'
################################################################
#
# Here are the database classes for persisting data.
#   Each has a "list" and "linelist" method (which are really just an application-
#   specific "to_string")
#
# We also use "has_many", "belongs_to" and the like to set up
# the foreign keys in each table.
#
# Note that the structure of these tables is deeply connected
# to the ".rb" files in the project "migrate" folder.    It is
# the action of the "rake db:migrate" and "rake db:rollback" console
# commands to create and delete, respectively, the databases.
# (either locally in test mode, on on heroku or any other cloud service)
#
# There are Four tables:
#    Transaction - this is a cash ledger.   It logs all receipts and disbursments
#    Logs - this is the inventory of raw stock (wooden logs) we have in stock.   
#            (Yes, an unfortunate name, given the many uses in computerworld for
#             the word "Log").   Atribute is the type of tree, i.e. White Ash or Maple
#            in the case of baseball bats; for our use it's just a string
#    Blanks - Rectangular peices of wood, cut from logs.   Attribute: Length
#    Turnings - Blanks are cut on a lathe into the proper shape.  Attribute: which league's shape.
#    Bats - After varnishing and paint-stamping a Turning, you have a finished bat.
#
#   One other attribute the Logs, Blanks, Turnings, and Bats have: a "consumed" boolean.
#   when an instance of Logs, Blanks, Turnings, or Bats is moved along in the flow, it is not deleted.
#   rather, it is marked consumed.   This maintains a full journal record of every log, every turning, etc. 
#   This is by intent; for future use, we could write, for example, queries to determine what type of wood
#   a particular bat was made from.  
#
################################################################



class Transaction < ActiveRecord::Base
  def linelist
    "#{self.id} = #{self.dollars} (Postive is cash receipt, negative is disbursement)"
  end 
end

class Log < ActiveRecord::Base
  
  COST = 20.00
  
  has_many :blanks
  def linelist
    "#{self.id} = #{self.species}, consumed = #{self.consumed.to_s}"
  end

  def list
    [self.id.to_s, self.species, self.consumed.to_s]
  end
end

class Blank < ActiveRecord::Base
  belongs_to :log
  has_one :turning
  def linelist
    "#{self.id} = #{self.log.species}, #{self.length.to_s}, consumed = #{self.consumed.to_s}"
  end
  def list
    [self.id.to_s, self.length.to_s, self.consumed.to_s]
  end
end

class Turning < ActiveRecord::Base
  belongs_to :blank
  has_one :bat
  def linelist
    "#{self.id} = #{self.blank.log.species}, #{self.blank.length}, #{self.league}, consumed = #{self.consumed.to_s}"
  end
  def list
    [self.id.to_s, self.league, self.consumed.to_s]
  end
end

class Bat < ActiveRecord::Base
  
  PRICE = 10.00
  
  belongs_to :turning
  def linelist
    "#{self.id} = #{self.turning.blank.log.species}, #{self.turning.blank.length}, #{self.turning.league}, #{self.model}, consumed = #{self.consumed.to_s}"
  end
  def list
    [self.id.to_s, self.model, self.consumed.to_s]
  end
end

