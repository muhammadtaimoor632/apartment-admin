<?php

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

class FDP_CPT_Webpages {

    public function __construct() {
        add_action( 'init', array( $this, 'register_cpt' ) );
        add_filter( 'template_include', array( $this, 'load_custom_template' ) );
    }

    public function load_custom_template( $template ) {
        if ( is_singular( 'fluent_dynamic_page' ) ) {
            $custom_template = FF_DYNAMIC_PAGES_DIR . 'templates/single-fluent_dynamic_page.php';
            if ( file_exists( $custom_template ) ) {
                return $custom_template;
            }
        }
        return $template;
    }

    public function register_cpt() {
        $labels = array(
            'name'                  => _x( 'Dynamic Webpages', 'Post type general name', 'fluent-dynamic-pages' ),
            'singular_name'         => _x( 'Dynamic Webpage', 'Post type singular name', 'fluent-dynamic-pages' ),
            'menu_name'             => _x( 'Dynamic Webpages', 'Admin Menu text', 'fluent-dynamic-pages' ),
            'name_admin_bar'        => _x( 'Dynamic Webpage', 'Add New on Toolbar', 'fluent-dynamic-pages' ),
            'add_new'               => __( 'Add New', 'fluent-dynamic-pages' ),
            'add_new_item'          => __( 'Add New Dynamic Webpage', 'fluent-dynamic-pages' ),
            'new_item'              => __( 'New Dynamic Webpage', 'fluent-dynamic-pages' ),
            'edit_item'             => __( 'Edit Dynamic Webpage', 'fluent-dynamic-pages' ),
            'view_item'             => __( 'View Dynamic Webpage', 'fluent-dynamic-pages' ),
            'all_items'             => __( 'All Dynamic Webpages', 'fluent-dynamic-pages' ),
            'search_items'          => __( 'Search Dynamic Webpages', 'fluent-dynamic-pages' ),
            'not_found'             => __( 'No Dynamic Webpages found.', 'fluent-dynamic-pages' ),
            'not_found_in_trash'    => __( 'No Dynamic Webpages found in Trash.', 'fluent-dynamic-pages' ),
        );

        $args = array(
            'labels'             => $labels,
            'public'             => true,
            'publicly_queryable' => true,
            'show_ui'            => true,
            'show_in_menu'       => true,
            'query_var'          => true,
            'rewrite'            => array( 'slug' => 'dynamic-webpage' ),
            'capability_type'    => 'post',
            'has_archive'        => false,
            'hierarchical'       => false,
            'menu_position'      => null,
            'menu_icon'          => 'dashicons-media-document',
            'supports'           => array( 'title', 'author', 'thumbnail' ),
        );

        register_post_type( 'fluent_dynamic_page', $args );
    }
}
