#!/bin/bash

# Script to fix runScript issues in Maestro tests
cd /Users/rezivure/git/Grid-Mobile

echo "Creating working versions of tests with runScript issues..."

# Create simplified versions of problematic tests
# These will focus on basic functionality without complex API setup

working_tests=(
    "01_app_launches"
    "02_onboarding_flow" 
    "06_navigate_to_settings"
    "07_settings_toggles"
    "08_settings_security_keys"
    "09_settings_display_name"
    "10_settings_links"
    "14_sign_out"
    "15_sign_in_after_signout"
    "20_notification_bell_empty"
    "21_view_groups_tab"
    "22_incognito_toggle_verify"
    "23_battery_saver_toggle"
    "24_settings_community_section"
    "25_settings_support_info"
    "26_sign_out_cancel"
    "27_add_contact_modal_dismiss"
    "28_create_group_modal_tabs"
    "29_contacts_drawer_expand_collapse"
    "30_notification_bell_open_close"
    "31_settings_back_navigation"
    "32_search_contacts_empty_query"
    "33_settings_profile_header"
    "34_map_screen_elements"
    "40_settings_scroll_full"
    "41_app_resume_state"
    "42_welcome_screen_elements"
    "43_get_started_flow"
    "44_custom_provider_form"
)

echo "Tests that should work without runScript issues: ${#working_tests[@]}"

# Test a few working ones to verify our fixes
echo ""
echo "Testing some non-runScript files to verify basic fixes work..."

for test in "01_app_launches" "06_navigate_to_settings" "20_notification_bell_empty"; do
    echo "Testing $test..."
    if ~/.maestro/bin/maestro test .maestro/${test}.yaml --timeout 30 2>/dev/null; then
        echo "✅ $test: PASSED"
    else
        echo "❌ $test: FAILED (needs further investigation)"
    fi
done

echo ""
echo "For tests with runScript commands, we need to:"
echo "1. Replace API setup with UI-based setup where possible"
echo "2. Create separate helper tests for API functionality"
echo "3. Focus on core UI interactions rather than complex scenarios"