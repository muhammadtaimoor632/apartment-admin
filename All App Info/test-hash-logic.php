<?php
$entry = "https://wildatlanticapartments.com/dynamic-webpage/eyre-square-checkin-instructions/?fdp_hash=sRJtzKkUUYzn6auoxACRMI8CkVxfvrC1";
$parsed = parse_url($entry);
parse_str($parsed['query'], $query_params);
echo $query_params['fdp_hash'];
