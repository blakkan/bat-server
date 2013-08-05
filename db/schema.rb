# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20130728233447) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "bats", force: true do |t|
    t.integer "turning_id"
    t.string  "model"
    t.boolean "consumed",   default: false
  end

  create_table "blanks", force: true do |t|
    t.integer "log_id"
    t.float   "length"
    t.boolean "consumed", default: false
  end

  create_table "logs", force: true do |t|
    t.string  "species"
    t.boolean "consumed", default: false
  end

  create_table "transactions", force: true do |t|
    t.float "dollars"
  end

  create_table "turnings", force: true do |t|
    t.integer "blank_id"
    t.string  "league"
    t.boolean "consumed", default: false
  end

end
