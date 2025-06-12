#!/usr/bin/env bash
set -e

# @describe Send a email.
# @option --recipient! The recipient of the email.
# @option --subject! The subject of the email.
# @option --body! The body of the email.

# @env EMAIL_SMTP_ADDR The SMTP Address, e.g. smtps://smtp.gmail.com:465
# @env EMAIL_SMTP_USER The SMTP User, e.g. alice@gmail.com
# @env EMAIL_SMTP_PASS The SMTP Password
# @env EMAIL_SENDER_NAME The sender name
# @env LLM_OUTPUT=/dev/stdout The output path

# Validate email address format
validate_email() {
    local email="$1"
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    [[ "$email" =~ $regex ]]
}

# Sanitize input to prevent injection attacks
sanitize_input() {
    local input="$1"
    # Remove null bytes and control characters except newlines and tabs
    echo "$input" | tr -d '\0' | sed 's/[[:cntrl:]]/ /g' | sed 's/\t/    /g' | sed 's/\n/\\n/g'
}

# Log messages with timestamp
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >&2
}

send_via_curl() {
    # Check if required SMTP credentials are available
    if [[ -z "$EMAIL_SMTP_ADDR" || -z "$EMAIL_SMTP_USER" || -z "$EMAIL_SMTP_PASS" ]]; then
        log_message "DEBUG" "Missing SMTP credentials"
        return 1
    fi
    
    # Validate SMTP address format
    if [[ ! "$EMAIL_SMTP_ADDR" =~ ^smtps?://[^:]+:[0-9]+$ ]]; then
        log_message "ERROR" "Invalid SMTP address format: $EMAIL_SMTP_ADDR"
        return 1
    fi
    
    local sender_name="${EMAIL_SENDER_NAME:-$(echo "$EMAIL_SMTP_USER" | awk -F'@' '{print $1}')}"
    local attempt=1
    local max_attempts=3
    local timeout=30
    
    # Escape special characters in sender name
    sender_name=$(echo "$sender_name" | sed 's/[<>\"]/\\&/g')
    
    # Create temporary file for email content
    local temp_file=$(mktemp)
    trap "rm -f '$temp_file'" EXIT
    
    # Build email with proper headers
    {
        echo "From: $sender_name <$EMAIL_SMTP_USER>"
        echo "To: $argc_recipient"
        echo "Subject: $(sanitize_input "$argc_subject")"
        echo "Date: $(date -R)"
        echo "Message-ID: <$(date +%Y%m%d%H%M%S).$$@$(hostname)>"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo "Content-Transfer-Encoding: 8bit"
        echo ""
        echo "$argc_body"
    } > "$temp_file"
    
    # Retry logic for transient failures
    while [[ $attempt -le $max_attempts ]]; do
        log_message "INFO" "Attempting to send email via SMTP (attempt $attempt/$max_attempts)"
        
        if curl -fsS --ssl-reqd \
            --url "$EMAIL_SMTP_ADDR" \
            --user "$EMAIL_SMTP_USER:$EMAIL_SMTP_PASS" \
            --mail-from "$EMAIL_SMTP_USER" \
            --mail-rcpt "$argc_recipient" \
            --upload-file "$temp_file" \
            --max-time "$timeout" \
            --connect-timeout 10 \
            2>&1 | tee /tmp/curl_error.log; then
            
            rm -f "$temp_file"
            return 0
        else
            local curl_exit_code=$?
            log_message "WARN" "SMTP send failed with exit code $curl_exit_code"
            
            # Check for specific error conditions
            if grep -q "authentication failed" /tmp/curl_error.log 2>/dev/null; then
                log_message "ERROR" "SMTP authentication failed"
                rm -f "$temp_file" /tmp/curl_error.log
                return 1
            fi
            
            ((attempt++))
            if [[ $attempt -le $max_attempts ]]; then
                sleep $((attempt * 2))  # Exponential backoff
            fi
        fi
    done
    
    rm -f "$temp_file" /tmp/curl_error.log
    return 1
}

send_via_mail() {
    local sender_name="$EMAIL_SENDER_NAME"
    
    # Check if mail command exists
    if ! command -v mail >/dev/null 2>&1; then
        log_message "DEBUG" "mail command not found"
        return 1
    fi
    
    # Create temporary file for body to handle special characters
    local temp_body=$(mktemp)
    trap "rm -f '$temp_body'" EXIT
    echo "$argc_body" > "$temp_body"
    
    # Build mail command with proper options
    local mail_cmd=("mail")
    
    # Add headers
    mail_cmd+=("-a" "Subject: $(sanitize_input "$argc_subject")")
    
    # If we have EMAIL_SMTP_USER, use it to construct sender info
    if [[ -n "$EMAIL_SMTP_USER" ]]; then
        sender_name="${sender_name:-$(echo "$EMAIL_SMTP_USER" | awk -F'@' '{print $1}')}"
        mail_cmd+=("-a" "From: $sender_name <$EMAIL_SMTP_USER>")
    elif [[ -n "$sender_name" ]]; then
        mail_cmd+=("-a" "From: $sender_name")
    fi
    
    # Add recipient
    mail_cmd+=("$argc_recipient")
    
    # Send email
    if "${mail_cmd[@]}" < "$temp_body" 2>&1 | tee /tmp/mail_error.log; then
        rm -f "$temp_body" /tmp/mail_error.log
        return 0
    else
        log_message "ERROR" "mail command failed: $(cat /tmp/mail_error.log 2>/dev/null)"
        rm -f "$temp_body" /tmp/mail_error.log
        return 1
    fi
}

main() {
    # Validate recipient email
    if ! validate_email "$argc_recipient"; then
        log_message "ERROR" "Invalid recipient email address: $argc_recipient"
        echo "Failed to send email: Invalid recipient email address" >> "$LLM_OUTPUT"
        return 1
    fi
    
    # Validate sender email if provided
    if [[ -n "$EMAIL_SMTP_USER" ]] && ! validate_email "$EMAIL_SMTP_USER"; then
        log_message "ERROR" "Invalid sender email address: $EMAIL_SMTP_USER"
        echo "Failed to send email: Invalid sender email address" >> "$LLM_OUTPUT"
        return 1
    fi
    
    # Check if subject is not empty
    if [[ -z "${argc_subject// }" ]]; then
        log_message "ERROR" "Email subject cannot be empty"
        echo "Failed to send email: Empty subject" >> "$LLM_OUTPUT"
        return 1
    fi
    
    # Check if body is not empty
    if [[ -z "${argc_body// }" ]]; then
        log_message "ERROR" "Email body cannot be empty"
        echo "Failed to send email: Empty body" >> "$LLM_OUTPUT"
        return 1
    fi
    
    # Try sending via curl first (only if SMTP credentials are available)
    if [[ -n "$EMAIL_SMTP_ADDR" ]] && send_via_curl; then
        log_message "INFO" "Email sent successfully via SMTP"
        echo "Email sent successfully via SMTP to $argc_recipient" >> "$LLM_OUTPUT"
        return 0
    fi
    
    # Fallback to mail command if curl fails
    if send_via_mail; then
        log_message "INFO" "Email sent successfully via mail command"
        echo "Email sent successfully via mail command to $argc_recipient" >> "$LLM_OUTPUT"
        return 0
    fi
    
    # Both methods failed
    log_message "ERROR" "Failed to send email using all available methods"
    echo "Failed to send email: neither SMTP nor mail command succeeded" >> "$LLM_OUTPUT"
    return 1
}

# Set up signal handlers for cleanup
trap 'log_message "WARN" "Script interrupted"; exit 130' INT TERM

eval "$(argc --argc-eval "$0" "$@")"
