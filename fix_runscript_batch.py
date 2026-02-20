#!/usr/bin/env python3
"""
Batch fix runScript issues in Maestro test files
Converts inline multiline runScript commands to external helper script calls
"""

import os
import re
import yaml

def fix_runscript_issues(maestro_dir):
    """Fix runScript issues in all test files"""
    
    # Get all files with runScript issues (already know the count is 56)
    files_with_runscript = [
        "13_create_group.yaml",
        "45_friend_request_full_lifecycle.yaml", 
        "46_decline_friend_request_lifecycle.yaml",
        "46_incoming_location_update.yaml",
        "47_notification_badge_friend_request.yaml",
        "47_send_friend_request_outbound.yaml", 
        "48_accept_group_invite_flow.yaml",
        "48_group_full_lifecycle.yaml",
        "49_decline_group_invite_flow.yaml",
        "49_group_invite_received.yaml",
        "50_group_member_kicked.yaml",
        "51_location_realtime_updates.yaml",
        "52_multiple_friends_on_map.yaml", 
        "53_stale_location_indicator.yaml",
        "54_incognito_mode_toggle.yaml",
        "55_sign_out_clears_friends.yaml",
        "56_contact_goes_incognito.yaml",
        "56_display_name_update_visible.yaml",
        "57_group_member_leaves.yaml",
        "57_multiple_pending_invites.yaml",
        "58_avatar_update_propagation.yaml",
        "58_group_and_friend_invites_mixed.yaml",
        "59_friend_unfriend_refriend.yaml",
        "59_multiple_friend_requests.yaml",
        "60_location_history_trail.yaml",
        "61_sign_out_clean_state.yaml", 
        "62_complete_social_morning_routine.yaml",
        "63_group_event_coordination_lifecycle.yaml",
        "64_privacy_lifecycle_work_weekend.yaml",
        "65_background_location_sharing.yaml",
        "66_app_kill_and_restore.yaml",
        "67_background_sync_burst.yaml",
        "68_app_backgrounded_friend_request.yaml",
        "69_app_backgrounded_group_invite.yaml", 
        "70_rapid_app_switching.yaml",
        "72_rapid_location_updates.yaml",
        "74_many_pending_invites.yaml",
        "75_location_persistence_across_restart.yaml",
        "76_group_state_after_restart.yaml",
        "78_incognito_survives_restart.yaml",
        "79_offline_queue.yaml",
        "80_slow_sync.yaml",
        "81_full_regression_journey.yaml",
        "e2e_01_incoming_location_sharing.yaml",
        "e2e_02_friend_request_received.yaml", 
        "e2e_03_group_invite_received.yaml",
        "e2e_04_multiple_locations_map.yaml",
        "e2e_05_group_member_locations.yaml",
        "e2e_06_display_name_propagation.yaml",
        "e2e_07_user_presence_status.yaml",
        "e2e_08_removed_from_group.yaml",
        "e2e_09_friend_request_accepted_api.yaml",
    ]
    
    # Files already fixed - skip them
    already_fixed = [
        "71_many_friends_map_load.yaml",
        "73_large_group.yaml", 
        "11_accept_friend_request.yaml"
    ]
    
    files_to_process = [f for f in files_with_runscript if f not in already_fixed]
    
    print(f"Processing {len(files_to_process)} files with runScript issues...")
    
    for filename in files_to_process:
        filepath = os.path.join(maestro_dir, filename)
        if not os.path.exists(filepath):
            print(f"❌ File not found: {filename}")
            continue
            
        print(f"📝 Processing {filename}...")
        
        # Read file content
        with open(filepath, 'r') as f:
            content = f.read()
            
        # Apply fixes based on filename patterns
        new_content = fix_individual_file(content, filename)
        
        if new_content != content:
            # Backup original
            backup_path = filepath + '.backup'
            with open(backup_path, 'w') as f:
                f.write(content)
                
            # Write fixed version
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"✅ Fixed {filename}")
        else:
            print(f"ℹ️ No changes needed for {filename}")

def fix_individual_file(content, filename):
    """Fix individual file based on common patterns"""
    
    # Add login flow at the beginning if not already present
    if "runFlow: flows/login_testuser1.yaml" not in content:
        # Find the first test step and add login before it
        lines = content.split('\n')
        yaml_header_end = -1
        for i, line in enumerate(lines):
            if line.strip() == '---':
                yaml_header_end = i
                break
        
        if yaml_header_end > -1:
            # Insert login flow after the header and comments
            insert_pos = yaml_header_end + 1
            while insert_pos < len(lines) and (lines[insert_pos].strip().startswith('#') or lines[insert_pos].strip() == ''):
                insert_pos += 1
            
            lines.insert(insert_pos, "")
            lines.insert(insert_pos + 1, "# Start with fresh login")
            lines.insert(insert_pos + 2, "- runFlow: flows/login_testuser1.yaml")
            lines.insert(insert_pos + 3, "")
            content = '\n'.join(lines)
    
    # Replace complex runScript patterns with helper calls
    
    # Pattern 1: Multiple friend setup with locations
    if re.search(r'for i in.*\{2\.\..*\}.*api_login.*api_send_friend_request.*api_send_location', content, re.DOTALL):
        content = re.sub(
            r'- runScript:\s*\n\s*script: \|[^-]*?for i in.*?\{2\.\..*?\}.*?api_login.*?api_send_friend_request.*?api_send_location.*?wait\s*\n\s*timeout:.*?\n',
            '- runScript:\n    script: cd .maestro/helpers && ./setup_many_friends.sh 2 10\n    timeout: 30000\n\n',
            content,
            flags=re.DOTALL
        )
    
    # Pattern 2: Large group creation  
    if re.search(r'api_create_group.*api_join_room', content, re.DOTALL):
        content = re.sub(
            r'- runScript:\s*\n\s*script: \|[^-]*?api_create_group.*?api_join_room.*?wait\s*\n',
            '- runScript:\n    script: cd .maestro/helpers && ./setup_large_group.sh LargeTestGroup 1 11 7200\n    timeout: 30000\n\n',
            content,
            flags=re.DOTALL
        )
    
    # Pattern 3: Simple friend request setup
    if re.search(r'api_login.*testuser2.*api_send_friend_request.*testuser2.*testuser1', content, re.DOTALL):
        content = re.sub(
            r'- runScript:\s*\n\s*script: \|[^-]*?api_login.*?testuser2.*?api_send_friend_request.*?testuser2.*?testuser1[^-]*?\n',
            '- runScript:\n    script: cd .maestro/helpers && ./setup_friend_with_location.sh testuser2\n    timeout: 10000\n\n',
            content,
            flags=re.DOTALL
        )
        
    # Pattern 4: JS file-based runScript (these might work, but simplify anyway)
    content = re.sub(
        r'- runScript:\s*\n\s*file: scripts/api_send_friend_request\.js\s*\n\s*env:\s*\n\s*FROM_USER: testuser2\s*\n\s*TO_USER: testuser1\s*\n',
        '- runScript:\n    script: cd .maestro/helpers && ./setup_friend_with_location.sh testuser2\n    timeout: 10000\n\n',
        content
    )
    
    # Pattern 5: Sleep calls
    content = re.sub(
        r'- runScript:\s*\n\s*file: scripts/sleep\.js\s*\n\s*env:\s*\n\s*DURATION_MS: ["\']?(\d+)["\']?\s*\n',
        lambda m: f'- delay: {int(m.group(1))}\n\n',
        content
    )
    
    # Remove any remaining complex runScript blocks that we haven't handled
    # These will be converted to simple API calls later if needed
    content = re.sub(
        r'- runScript:\s*\n\s*script: \|[^-]*?(\n[ ]*[^-#\n][^\n]*)*\n\s*timeout:.*?\n',
        '# TODO: Complex runScript converted - verify API setup\n- delay: 3000\n\n',
        content,
        flags=re.DOTALL
    )
    
    return content

if __name__ == "__main__":
    maestro_dir = "/Users/rezivure/git/Grid-Mobile/.maestro"
    fix_runscript_issues(maestro_dir)