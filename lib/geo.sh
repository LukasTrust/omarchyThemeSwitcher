#!/usr/bin/env bash
# geo.sh — sunrise/sunset times for a given lat/lon
#
# Public API:
#   geo_sun_times LAT LON TWILIGHT  →  prints "SUNRISE_HH:MM SUNSET_HH:MM"
#
# TWILIGHT: civil | nautical | astronomical | none
#
# Prefers sunwait(1) if present; falls back to a pure awk implementation of the
# NOAA solar position algorithm (accurate to ±2 minutes for most latitudes).

_geo_cache_file() {
    local lat="$1" lon="$2" twilight="$3"
    local tag="${lat}_${lon}_${twilight}"
    echo "${SWITCHER_STATE_DIR}/sun-cache-$(date '+%Y-%m-%d')-${tag//[^a-zA-Z0-9._-]/_}"
}

# Returns the depression angle for the given twilight type
_twilight_angle() {
    case "$1" in
        civil)         echo "6" ;;
        nautical)      echo "12" ;;
        astronomical)  echo "18" ;;
        none|*)        echo "0.833" ;;  # standard refraction-corrected horizon
    esac
}

# Compute via sunwait(1)
_geo_via_sunwait() {
    local lat="$1" lon="$2" twilight="$3"
    local angle; angle=$(_twilight_angle "$twilight")
    local lat_dir="N" lon_dir="E"
    (( $(echo "$lat < 0" | awk '{print ($1<0)}') )) && lat_dir="S" && lat="${lat#-}"
    (( $(echo "$lon < 0" | awk '{print ($1<0)}') )) && lon_dir="W" && lon="${lon#-}"

    local out
    out=$(sunwait list civil "$lat${lat_dir}" "$lon${lon_dir}" 2>/dev/null) || return 1
    # sunwait list outputs "HH:MM HH:MM" (rise set in local time)
    echo "$out"
}

# Compute via awk (NOAA algorithm, public domain)
# Outputs "HH:MM HH:MM"
_geo_via_awk() {
    local lat="$1" lon="$2" zenith="$3"
    # zenith = 90 + depression angle
    # none/horizon uses 90.833 (standard refraction), others add depression
    local zen
    case "$zenith" in
        0.833) zen="90.833" ;;
        *)     zen=$(awk "BEGIN{printf \"%.3f\", 90 + $zenith}") ;;
    esac

    awk -v lat="$lat" -v lon="$lon" -v zenith="$zen" '
    BEGIN {
        PI = 3.14159265358979
        DEG = PI / 180
        RAD = 180 / PI

        # Julian date for today (UTC noon)
        cmd = "date -u +\"%Y %m %d\""
        cmd | getline datestr
        close(cmd)
        split(datestr, d, " ")
        Y = d[1]; M = d[2]; D = d[3]
        # Julian Day Number
        A = int((14 - M) / 12)
        y = Y + 4800 - A
        m = M + 12 * A - 3
        JD = D + int((153*m+2)/5) + 365*y + int(y/4) - int(y/100) + int(y/400) - 32045
        JD = JD - 0.5  # noon → midnight

        # Use JD + 0.5 for sunrise/sunset (iterate for accuracy)
        for (pass = 0; pass <= 1; pass++) {
            t = JD - 2451545.0  # J2000.0

            # Mean longitude and anomaly
            L0 = 280.46646 + 36000.76983 * (t/36525)
            L0 = L0 - int(L0/360)*360
            M0 = 357.52911 + 35999.05029 * (t/36525) - 0.0001537 * (t/36525)^2
            M0_r = M0 * DEG

            # Equation of center
            C = (1.914602 - 0.004817*(t/36525) - 0.000014*(t/36525)^2) * sin(M0_r) \
              + (0.019993 - 0.000101*(t/36525)) * sin(2*M0_r) \
              + 0.000289 * sin(3*M0_r)

            # Sun true longitude & apparent longitude
            sun_lon = L0 + C
            omega = 125.04 - 1934.136 * (t/36525)
            lam = sun_lon - 0.00569 - 0.00478 * sin(omega * DEG)

            # Mean obliquity of ecliptic + correction
            eps0 = 23 + 26/60.0 + 21.448/3600.0 - (46.8150/3600)*( t/36525) \
                 - (0.00059/3600)*(t/36525)^2 + (0.001813/3600)*(t/36525)^3
            eps = eps0 + 0.00256 * cos(omega * DEG)

            # Right ascension & declination
            RA = atan2(cos(eps*DEG)*sin(lam*DEG), cos(lam*DEG)) * RAD
            decl = asin(sin(eps*DEG)*sin(lam*DEG)) * RAD

            # Equation of time (minutes)
            y2 = tan(eps/2 * DEG)^2
            EqT = 4 * RAD * (y2*sin(2*L0*DEG) - 2*0.016708634*sin(M0_r) \
                + 4*0.016708634*y2*sin(M0_r)*cos(2*L0*DEG) \
                - 0.5*y2^2*sin(4*L0*DEG) - 1.25*0.016708634^2*sin(2*M0_r))

            # Hour angle
            cos_HA = (cos(zenith*DEG) - sin(lat*DEG)*sin(decl*DEG)) \
                   / (cos(lat*DEG)*cos(decl*DEG))

            if (cos_HA < -1) { print "00:00 00:00"; exit }
            if (cos_HA >  1) { print "12:00 12:00"; exit }

            HA = acos(cos_HA) * RAD

            # Solar noon (minutes from midnight UTC)
            noon_utc = 720 - 4*lon - EqT

            # Sunrise / sunset in minutes from midnight UTC
            rise_utc = noon_utc - HA * 4
            set_utc  = noon_utc + HA * 4

            # Convert to local time via system TZ offset (minutes)
            tz_cmd = "date +%z"
            tz_cmd | getline tz_str
            close(tz_cmd)
            sign = (substr(tz_str,1,1) == "-") ? -1 : 1
            tz_h = substr(tz_str,2,2)+0
            tz_m = substr(tz_str,4,2)+0
            tz_offset = sign * (tz_h*60 + tz_m)

            rise_local = rise_utc + tz_offset
            set_local  = set_utc  + tz_offset

            # Wrap to [0, 1440)
            while (rise_local < 0)    rise_local += 1440
            while (rise_local >= 1440) rise_local -= 1440
            while (set_local < 0)     set_local  += 1440
            while (set_local >= 1440) set_local  -= 1440

            rise_h = int(rise_local / 60)
            rise_m = int(rise_local % 60)
            set_h  = int(set_local / 60)
            set_m  = int(set_local % 60)

            printf "%02d:%02d %02d:%02d\n", rise_h, rise_m, set_h, set_m
            exit
        }
    }' /dev/null
}

# Main public function
# Usage: geo_sun_times LAT LON TWILIGHT
# Prints: "HH:MM HH:MM" (sunrise sunset)
geo_sun_times() {
    local lat="$1" lon="$2" twilight="${3:-civil}"

    local cache; cache=$(_geo_cache_file "$lat" "$lon" "$twilight")
    if [[ -f "$cache" ]]; then
        cat "$cache"
        return 0
    fi

    local result
    if command -v sunwait &>/dev/null; then
        result=$(_geo_via_sunwait "$lat" "$lon" "$twilight" 2>/dev/null) || result=""
    fi

    if [[ -z "$result" ]]; then
        local angle; angle=$(_twilight_angle "$twilight")
        result=$(_geo_via_awk "$lat" "$lon" "$angle")
    fi

    if [[ -n "$result" ]]; then
        echo "$result" > "$cache"
        echo "$result"
    else
        return 1
    fi
}
