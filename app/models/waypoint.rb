class Waypoint < ApplicationRecord
  belongs_to :flight

  enum format: %i[dm dms d utm mgrs]

  default_scope { order(:number) }

  before_validation :set_number
  after_destroy :destroyed

  validates :number, uniqueness: { scope: :flight_id }

  def to_s
    Position.new(latitude: latitude, longitude: longitude, dme: dme).to_s(format: format || :dm, precision: precision || 3)
  end

  def coords
    Position.new(latitude: latitude, longitude: longitude, dme: dme).coords(format: format || :dm, precision: precision || 3)
  end

  def position
    to_s
  end

  def format
    (self[:format] ||= :dms).to_sym
  end

  def precision
    self[:precision] ||= 3
  end

  def export
    sprintf '%s EL%05d T%s %s', Position.new(latitude: latitude, longitude: longitude).to_s(format: :export),
            elevation.to_i,
            tot&.strftime('%H%M%S') || '000000',
            name

  end

  def previous
    return nil unless number > 1

    flight.waypoints.find_by number: number - 1
  end

  def next
    return nil unless number < flight.waypoints.count

    flight.waypoints.find_by number: number + 1
  end

  private

  def set_number
    self.number ||= flight.waypoints.count + 1
  end

  def destroyed
    successors = flight.waypoints.where('number > ?', number)
    successors.each do |wp|
      wp.update number: wp.number - 1
    end
  end
end
