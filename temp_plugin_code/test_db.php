<?php
require_once('../../wp-load.php');
global $wpdb;
$row = $wpdb->get_row("SELECT response FROM {$wpdb->prefix}fluentform_submissions ORDER BY id DESC LIMIT 1");
if ($row) {
    print_r(array_keys(json_decode($row->response, true)));
}
