<?php
require_once('/Users/muhammadtaimoor/Desktop/Custom webpage/wp-load.php');
global $wpdb;
$form = $wpdb->get_row("SELECT form_fields FROM {$wpdb->prefix}fluentform_forms ORDER BY id DESC LIMIT 1");
if ($form) {
    print_r(json_decode($form->form_fields, true));
}
