#!/bin/bash
source settings.conf
arrUrl="http://localhost:8989"
arrApiKey="mock"
sonarrSeriesEpisodeTrimmerTag="daily"

# Test function mimicking the current code
test_current() {
    for seriesId in {1..100}; do
        seriesData=$(curl -s "$arrUrl/api/v3/series/$seriesId?apikey=$arrApiKey")
        seriesTags=$(echo $seriesData | jq -r ".tags[]" 2>/dev/null)
        if [ -z "$sonarrSeriesEpisodeTrimmerTag" ]; then
            tagMatch="false"
        else
            tagMatch="false"
            for tagId in $seriesTags; do
                tagLabel="$(curl -s "$arrUrl/api/v3/tag/$tagId?apikey=$arrApiKey" | jq -r ".label" 2>/dev/null)"
                if  [ "$sonarrSeriesEpisodeTrimmerTag" == "$tagLabel" ]; then
                    tagMatch="true"
                    break
                fi
            done
        fi
    done
}

# Test function mimicking the optimized code
test_optimized() {
    # Fetch all tags once
    allTagsData=$(curl -s "$arrUrl/api/v3/tag?apikey=$arrApiKey")

    for seriesId in {1..100}; do
        seriesData=$(curl -s "$arrUrl/api/v3/series/$seriesId?apikey=$arrApiKey")
        seriesTags=$(echo $seriesData | jq -r ".tags[]" 2>/dev/null)
        if [ -z "$sonarrSeriesEpisodeTrimmerTag" ]; then
            tagMatch="false"
        else
            tagMatch="false"
            for tagId in $seriesTags; do
                # Extract tagLabel from the pre-fetched JSON
                tagLabel=$(echo "$allTagsData" | jq -r ".[] | select(.id == $tagId) | .label" 2>/dev/null)
                if  [ "$sonarrSeriesEpisodeTrimmerTag" == "$tagLabel" ]; then
                    tagMatch="true"
                    break
                fi
            done
        fi
    done
}

echo "Measuring current implementation..."
time test_current

echo "Measuring optimized implementation..."
time test_optimized
