<?php
if (!defined('ABSPATH')) {
    exit;
}

// Standalone template for dynamic pages (no header/footer)
?>
<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo('charset'); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <?php if (!current_theme_supports('title-tag')) : ?>
        <title><?php wp_title('|', true, 'right'); ?></title>
    <?php endif; ?>
    <?php wp_head(); ?>
    <style>
        body.single-fluent_dynamic_page {
            margin: 0;
            padding: 0;
            background-color: #f8f9fa;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen-Sans, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
            color: #333;
        }
        .fdp-standalone-container {
            max-width: 900px;
            margin: 40px auto;
            padding: 30px;
            background: #ffffff;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.05);
            border-radius: 10px;
        }
        .fdp-page-title {
            margin-top: 0;
            margin-bottom: 25px;
            font-size: 2.2rem;
            color: #1e293b;
            border-bottom: 2px solid #f1f5f9;
            padding-bottom: 15px;
            text-align: center;
        }
        .fdp-page-content {
            font-size: 1.05rem;
            line-height: 1.6;
        }
        @media (max-width: 768px) {
            .fdp-standalone-container {
                margin: 0;
                border-radius: 0;
                box-shadow: none;
                min-height: 100vh;
                padding: 20px 15px;
            }
            .fdp-page-title {
                font-size: 1.8rem;
            }
        }
    </style>
</head>
<body <?php body_class(); ?>>

    <div class="fdp-standalone-container">
        <?php
        while (have_posts()) :
            the_post();
            ?>
            <h1 class="fdp-page-title"><?php the_title(); ?></h1>
            <div class="fdp-page-content">
                <?php the_content(); ?>
            </div>
            <?php
        endwhile;
        ?>
    </div>

    <?php wp_footer(); ?>
</body>
</html>
