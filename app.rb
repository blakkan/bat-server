require 'sinatra'
require 'pg'
require 'active_record'
require 'sinatra/activerecord'
require 'haml'


################################################################
#
# And here are the database classes for persisting data
#
################################################################
class Log < ActiveRecord::Base
  has_many :blanks
  def linelist
    "#{self.id} = #{self.species}, consumed = #{self.consumed.to_s}"
  end
end

class Blank < ActiveRecord::Base
  belongs_to :log
  has_one :turning
  def linelist
    "#{self.id} = #{self.log.species}, #{self.length.to_s}, consumed = #{self.consumed.to_s}"
  end
end

class Turning < ActiveRecord::Base
  belongs_to :blank
  has_one :bat
  def linelist
    "#{self.id} = #{self.blank.log.species}, #{self.blank.length}, #{self.league}, consumed = #{self.consumed.to_s}"
  end
end

class Bat < ActiveRecord::Base
  belongs_to :turning
  def linelist
    "#{self.id} = #{self.turning.blank.log.species}, #{self.turning.blank.length}, #{self.turning.league}, #{self.model}, consumed = #{self.consumed.to_s}"
  end
end

############################################################
#
# Here is where we do our setups 
#
############################################################


configure do 
  ############################################################
  #
  # Hook up the database.   Here we're using a local file, but
  # we could easily change this to hook up to heroku
  #
  # We'll use active record to wrap this stuff for our models
  #
  ############################################################

  #This line is the magic for Heroku; heroku will give us a URL in the
  # environment variable.  But if we don't get that environment variable,
  # then we're running locally (it would seem...)
  db = URI.parse(ENV['DATABASE_URL'] || 'postgres://basic:basic@localhost/factorydb')

  ActiveRecord::Base.establish_connection(
  :adapter  => db.scheme == 'postgres' ? 'postgresql' : db.scheme,
  :host     => db.host,
  :username => db.user,
  :password => db.password,
  :database => db.path[1..-1],
  :encoding => 'utf8'
  )

end
#########################################################
#
# Here are the routes and controllers
#
#########################################################

#
# These controllers return the inventory
#
get '/logs' do
  @items = Log.all.to_a
  @headText = "Log Record"
  haml :template_for_list
end

get '/blanks' do
  @items = Blank.all.to_a
  @headText = "Blanks Record"
  haml :template_for_list
end

get '/turnings' do
  @items = Turning.all.to_a
  @headText = "Turnings Record"
  haml :template_for_list
end

get '/bats' do
  @items = Bat.all.to_a
  @headText = "Bats now in stock"
  haml :template_for_list
end

#
# These controllers drive the actions
#

get '/buy/:species' do
  Log.create(:species => params[:species])
  redirect '/logs'
end



get '/cut/:logId/:length' do

  if Log.find(params[:logId].to_s.to_i).consumed == true
    @errorMessage = "Attempt to cut a log (id = #{params[:logId].to_s}) which has already been cut"
    haml :template_for_fail
  else
   
    #should probably put a transaction around these 
    Log.update(params[:logId].to_s.to_i, :consumed => true )
    #Get a random number of blanks from each log
    (Random.rand(4)+2).times do
      ##puts "Logid: #{params[:logId].to_s}  Length: #{params[:length].to_s}"
      Log.find(params[:logId].to_s.to_i).blanks.create(:length => params[:length])
    end

    redirect '/blanks'
  end
end

get '/turn/:blankId/:league' do
  if Blank.find(params[:blankId].to_s.to_i).consumed == true
    @errorMessage = "Attempt to turn a blank (id = #{params[:blankId].to_s}) which has already been turned"
    haml :template_for_fail
  else
    #should probably put a transaction around these
    Blank.update(params[:blankId].to_s.to_i, :consumed => true )
    Blank.find(params[:blankId].to_s).create_turning(:league => params[:league])
    redirect '/turnings'
  end
end

get '/finish/:turningId/:model' do
  if Turning.find(params[:turningId].to_s.to_i).consumed == true
    @errorMessage = "Attempt to finish a turning (id = #{params[:turningId].to_s}) which has already been turned"
    haml :template_for_fail
  else
    #should probably put a transaction around these
    Turning.update(params[:turningId].to_s.to_i, :consumed => true )
    Turning.find(params[:turningId].to_s.to_i).create_bat(:model => params[:model])
    redirect '/bats'
  end
end

get '/sell/:batId' do
  if Bat.find(params[:batId].to_s.to_i).consumed == true
    @errorMessage = "Attempt to sell a bat (id = #{params[:batId].to_s}) which has already been sold"
    haml :template_for_fail
  else
    Bat.update(params[:batId].to_s.to_i, :consumed => true )
    redirect '/bats'
  end
end

#
#  This is where the SOA portion will be
#

put '/command' do
  [ 200, { 'Content-type' => 'text/plain'}, [request.body.read]]
end


__END__

######################################################
#
# And Sinatra's inline views are right here
#
######################################################


@@template_for_list
%h1= @headText
%h3= "Start of List"
%table
  %tbody
    - @items.each do |row|
      %tr
        %td= row.linelist
%h3= "End of list"

@@template_for_ack
%h3= "Completed"

@@template_for_fail
%h3= "Error: " + @errorMessage
