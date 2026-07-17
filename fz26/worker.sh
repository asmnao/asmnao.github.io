#!/bin/bash

URL_HEAD="https://tmsqr.app/api/timetable/690cb51863cc9/stage"

DATADIR="."
TMPDIR="$DATADIR/tmp"

fetch () {
	start=$(date -Is)

	TAG=$1
	URL="$URL_HEAD/$TAG"
	OUTPUT="$TMPDIR/$TAG.json"
	LOG="$TMPDIR/$TAG.log"
	JOB="$TMPDIR/$TAG.job.json"

	{
	set -o pipefail
	curl "$URL" | LC_ALL=C jq '
.startTime as $day
| [
    .stages[]
    | .title as $stage
    | .performances[]
    | {
        day: {
					sort: $day,
					_: ($day | strptime("%Y-%m-%d %H:%M:%S") | strftime("%a"))
				},
        artist: .artist,
        stage: $stage,
        when: {
					 sort: .start,
					 _: (
							(.start | strptime("%Y-%m-%d %H:%M:%S") | strftime("%H:%M"))
							+ "-"
							+ (.end | strptime("%Y-%m-%d %H:%M:%S") | strftime("%H:%M"))
						),
					},
      }
]
'  > $OUTPUT
	} > $LOG 2>&1
	rc=$?
	end=$(date -Is)

	 jq 	-n \
			--arg tag "$TAG" \
			--arg start "$start" \
			--arg end "$end" \
			--argjson exit_code "$rc" \
			--slurpfile output "$OUTPUT" \
			--rawfile log "$LOG" \
			'{
			  tag: $tag,
			  success: ($exit_code == 0),
			  started_at: $start,
			  finished_at: $end,
			  log: $log,
			  output: $output[0] // [],
			}' >"$JOB"
}

echo "Ensuring $TMPDIR exists."
mkdir -p "$TMPDIR"

TARGETS="65535 65536 65537 65538"

for f in $TARGETS
do
	echo "Fetching $f."
	fetch "$f"
	sleep 2
done
echo

jq --arg time $(date -Is) -s '
  if all(.success) then
    {
      success: true,
      time: $time,
      output: (map(.output) | add),
    }
  else
    {
      success: false,
      time: $time,
      logs: (
        map(select(.success | not))
        | map({(.tag): .log})
        | add
      ),
    }
  end
' "$TMPDIR"/*.job.json > "$TMPDIR"/result.json

if jq -e '.success == false' "$TMPDIR"/result.json >/dev/null; then
	echo "Something went wrong. Not replacing old result.json."
	echo
	cat "$TMPDIR"/result.json | jq
	exit 1
fi

echo "Looking good. Going forward with new result.json."
cp "$TMPDIR"/result.json "$DATADIR"/result.json
