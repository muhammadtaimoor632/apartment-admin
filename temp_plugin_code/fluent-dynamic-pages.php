<?php
/**
 * Plugin Name: Fluent Forms Dynamic Webpages
 * Plugin URI:  https://example.com/
 * Description: Maps Fluent Forms to specific webpages and populates them dynamically with submission data.
 * Version:     1.0.0
 * Author:      Your Name
 * License:     GPL-2.0+
 */

if (!defined('ABSPATH')) {
    exit; // Exit if accessed directly.
}

define('FF_DYNAMIC_PAGES_VERSION', '1.0.0');
define('FF_DYNAMIC_PAGES_DIR', plugin_dir_path(__FILE__));
define('FF_DYNAMIC_PAGES_URL', plugin_dir_url(__FILE__));

/**
 * Main Plugin Class
 */
class Fluent_Dynamic_Pages
{

    private static $instance = null;

    public static function get_instance()
    {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct()
    {
        $this->includes();
        $this->init();
    }

    private function includes()
    {
        require_once FF_DYNAMIC_PAGES_DIR . 'includes/class-cpt-webpages.php';
        require_once FF_DYNAMIC_PAGES_DIR . 'includes/class-admin-meta-boxes.php';
        require_once FF_DYNAMIC_PAGES_DIR . 'includes/class-fluent-integration.php';
        require_once FF_DYNAMIC_PAGES_DIR . 'includes/class-generated-links-log.php';
        require_once FF_DYNAMIC_PAGES_DIR . 'includes/class-woocommerce-integration.php';
    }

    private function init()
    {
        new FDP_CPT_Webpages();
        if (is_admin()) {
            new FDP_Admin_Meta_Boxes();
            new FDP_Generated_Links_Log();
        }
        new FDP_Fluent_Integration();
        new FDP_WooCommerce_Integration();
    }
}

function ff_dynamic_pages_init()
{
    Fluent_Dynamic_Pages::get_instance();
}

add_action('plugins_loaded', 'ff_dynamic_pages_init');
