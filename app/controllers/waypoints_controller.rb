class WaypointsController < ApplicationController
  before_action :set_flight
  before_action :set_waypoint, only: %i[update destroy up down]
  around_action :wrap_in_transaction, only: [:create, :up, :down]

  def index
    wps = Settings.theaters[@flight.theater].waypoints.map do |wp|
      pos = position(wp)
      { name: wp.name, dme: pos.dme || '', pos: pos.coords, lat: pos.latitude, lon: pos.longitude }
    end
    wps = wps.select { |wp| wp[:name].downcase.include? params[:q].downcase } if params[:q]
    render json: wps
  end

  def create
    pos, wp = to_position
    attribs = { latitude: pos.latitude,
                longitude: pos.longitude,
                dme: pos.dme,
                name: wp[:name],
                elevation: wp[:elev],
                tot: wp[:tot],
                format: wp[:fmt],
                precision: wp[:prec]
    }
    if wp[:insert].present?
      first_wp_to_move = @flight.waypoints.find wp[:insert]
      attribs.merge! number: first_wp_to_move.number
      @flight.waypoints.where('number >= ?', first_wp_to_move.number).reorder(number: :desc).each do |e|
        e.update! number: e.number + 1
      end
    end
    @waypoint = @flight.waypoints.build attribs
    @waypoint.save!
    render @waypoint
  end

  def update
    pos, wp = to_position
    if @waypoint.update latitude: pos.latitude,
                        longitude: pos.longitude,
                        dme: pos.dme,
                        name: wp[:name],
                        elevation: wp[:elev],
                        tot: wp[:tot],
                        format: wp[:fmt],
                        precision: wp[:prec]
      render @waypoint
    else
      head :bad_request
    end
  end

  def destroy
    @waypoint.destroy
    redirect_to flight_path(@flight), notice: 'Waypoint was successfully destroyed.'
  end

  def copy_from
    @flight.waypoints.destroy_all
    src_flight = Flight.find params[:waypoints][:flight]
    src_flight.waypoints.each do |wp|
      new_wp = wp.dup
      new_wp.flight = @flight
      new_wp.save!
    end
    redirect_to flight_path(@flight), notice: 'Waypoints successfully copied.'
  end

  def import
    @flight.waypoints.destroy_all
    route = params[:route].split(/\|/).reject(&:empty?).drop(1)
    route.each_with_index do |wp, i|
      name, lat, lon, alt = wp.split /!/
      @flight.waypoints.create name: name, latitude: lat, longitude: lon, elevation: alt
    end
    redirect_to flight_path(@flight), notice: 'Waypoints successfully imported.'
  end

  def export
    send_data export_data, filename: "mission_#{@flight.id}.txt", type: 'text/plain', disposition: :inline
  end

  def up
    prev = @waypoint.previous
    if prev
      prev.update! number: nil
      @waypoint.update! number: @waypoint.number - 1
      prev.update! number: @waypoint.number + 1
    end
    redirect_to flight_path(@flight)
  end

  def down
    next_waypoint = @waypoint.next
    if next_waypoint
      next_waypoint.update! number: nil
      @waypoint.update! number: @waypoint.number + 1
      next_waypoint.update! number: @waypoint.number - 1
    end
    redirect_to flight_path(@flight)
  end

  private

  def to_position
    wp = waypoint_params
    pos = Position.new latitude: wp[:lat], longitude: wp[:lon], pos: wp[:pos], dme: wp[:dme]
    [pos, wp]
  end

  def set_flight
    @flight = Flight.find(params[:flight_id])
  end

  def set_waypoint
    @waypoint = @flight.waypoints.find(params[:id])
  end

  def waypoint_params
    params.permit(:name, :dme, :lat, :lon, :pos, :elev, :tot, :fmt, :prec, :insert)
  end

  def position(wp)
    Position.new(latitude: wp.lat, longitude: wp.lon, pos: wp.pos, dme: wp.dme)
  end

  def export_data
    @flight.waypoints.map(&:export).join("\n")
  end
end
