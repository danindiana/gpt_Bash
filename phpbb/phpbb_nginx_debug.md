```mermaid
flowchart TD
    Start([phpBB Not Working?]) --> CheckServices{Are services running?<br/>nginx, php-fpm, mariadb}
    
    CheckServices -->|No| StartServices[Start Services:<br/>sudo systemctl start nginx<br/>sudo systemctl start php8.4-fpm<br/>sudo systemctl start mariadb]
    StartServices --> CheckServices
    
    CheckServices -->|Yes| CheckNginxConfig{Nginx config valid?<br/>sudo nginx -t}
    
    CheckNginxConfig -->|No| FixNginxSyntax[Fix Nginx Syntax:<br/>Check brackets, semicolons<br/>Validate server blocks]
    FixNginxSyntax --> ReloadNginx[sudo systemctl reload nginx]
    ReloadNginx --> CheckNginxConfig
    
    CheckNginxConfig -->|Yes| CheckSiteEnabled{phpBB site enabled?<br/>ls /etc/nginx/sites-enabled/}
    
    CheckSiteEnabled -->|No| EnableSite[Enable phpBB Site:<br/>sudo rm /etc/nginx/sites-enabled/default<br/>sudo ln -sf /etc/nginx/sites-available/phpbb /etc/nginx/sites-enabled/]
    EnableSite --> ReloadNginx2[sudo systemctl reload nginx]
    ReloadNginx2 --> CheckSiteEnabled
    
    CheckSiteEnabled -->|Yes| CheckDocRoot{Document root correct?<br/>Should be /var/www/html/forum}
    
    CheckDocRoot -->|No| FixDocRoot[Fix Document Root:<br/>Edit nginx config<br/>root /var/www/html/forum;]
    FixDocRoot --> ReloadNginx3[sudo systemctl reload nginx]
    ReloadNginx3 --> CheckDocRoot
    
    CheckDocRoot -->|Yes| CheckPHPSocket{PHP-FPM socket exists?<br/>/run/php/php8.4-fpm.sock}
    
    CheckPHPSocket -->|No| FixPHPFPM[Fix PHP-FPM:<br/>sudo systemctl restart php8.4-fpm<br/>Check pool config]
    FixPHPFPM --> CheckPHPSocket
    
    CheckPHPSocket -->|Yes| CheckFastCGI{FastCGI config correct?<br/>SCRIPT_FILENAME parameter}
    
    CheckFastCGI -->|No| FixFastCGI[Fix FastCGI Config:<br/>fastcgi_param SCRIPT_FILENAME<br/>$document_root$fastcgi_script_name]
    FixFastCGI --> ReloadNginx4[sudo systemctl reload nginx]
    ReloadNginx4 --> CheckFastCGI
    
    CheckFastCGI -->|Yes| CheckFileExists{phpBB files exist?<br/>/var/www/html/forum/app.php}
    
    CheckFileExists -->|No| ReinstallPHPBB[Reinstall phpBB:<br/>Download & extract<br/>Run composer install]
    ReinstallPHPBB --> CheckFileExists
    
    CheckFileExists -->|Yes| CheckPermissions{File permissions correct?<br/>Owner: www-data:www-data}
    
    CheckPermissions -->|No| FixPermissions[Fix Permissions:<br/>sudo chown -R www-data:www-data /var/www/html/forum<br/>sudo chmod 777 cache store files]
    FixPermissions --> CheckPermissions
    
    CheckPermissions -->|Yes| CheckDatabase{Database accessible?<br/>mysql -u phpbb_user -p phpbb_forum}
    
    CheckDatabase -->|No| FixDatabase[Fix Database:<br/>Check MariaDB running<br/>Recreate user/database<br/>Check credentials]
    FixDatabase --> CheckDatabase
    
    CheckDatabase -->|Yes| TestWebAccess{Web access working?<br/>curl localhost/test.php}
    
    TestWebAccess -->|No| CheckErrorLogs[Check Error Logs:<br/>sudo tail /var/log/nginx/error.log<br/>sudo tail /var/log/php8.4-fpm.log]
    
    CheckErrorLogs --> PrimaryScriptUnknown{Error: Primary script unknown?}
    PrimaryScriptUnknown -->|Yes| FixScriptFilename[Fix SCRIPT_FILENAME:<br/>Ensure path is correct<br/>Check try_files directive]
    FixScriptFilename --> TestWebAccess
    
    CheckErrorLogs --> PermissionDenied{Error: Permission denied?}
    PermissionDenied -->|Yes| FixPermissions
    
    CheckErrorLogs --> SocketError{Error: Socket connection?}
    SocketError -->|Yes| FixPHPFPM
    
    CheckErrorLogs --> ConfigError{Error: Config syntax?}
    ConfigError -->|Yes| FixNginxSyntax
    
    TestWebAccess -->|Yes| TestPHPBB{phpBB pages load?<br/>curl localhost/install/}
    
    TestPHPBB -->|No| CheckPHPBBConfig[Check phpBB Config:<br/>URL rewriting rules<br/>Install directory access]
    CheckPHPBBConfig --> FixRewrite[Fix URL Rewriting:<br/>Add proper location blocks<br/>Check install path]
    FixRewrite --> TestPHPBB
    
    TestPHPBB -->|Yes| CheckInstaller{Installer accessible?<br/>Browser: http://ip/install/}
    
    CheckInstaller -->|No| CheckInstallPerms[Check Install Permissions:<br/>chmod 755 install/<br/>Check .htaccess conflicts]
    CheckInstallPerms --> CheckInstaller
    
    CheckInstaller -->|Yes| Success([✅ Success!<br/>phpBB is working])
    
    %% Error handling paths
    CheckErrorLogs --> OtherError{Other errors?}
    OtherError -->|Yes| ManualDebug[Manual Debug:<br/>Check specific error message<br/>Search phpBB documentation<br/>Run troubleshoot script]
    ManualDebug --> CheckServices
    
    %% Styling
    classDef errorNode fill:#ffebee,stroke:#f44336,stroke-width:2px
    classDef successNode fill:#e8f5e8,stroke:#4caf50,stroke-width:2px
    classDef actionNode fill:#fff3e0,stroke:#ff9800,stroke-width:2px
    classDef checkNode fill:#e3f2fd,stroke:#2196f3,stroke-width:2px
    
    class Start,Success successNode
    class CheckServices,CheckNginxConfig,CheckSiteEnabled,CheckDocRoot,CheckPHPSocket,CheckFastCGI,CheckFileExists,CheckPermissions,CheckDatabase,TestWebAccess,TestPHPBB,CheckInstaller checkNode
    class StartServices,FixNginxSyntax,EnableSite,FixDocRoot,FixPHPFPM,FixFastCGI,ReinstallPHPBB,FixPermissions,FixDatabase,FixScriptFilename,FixRewrite,CheckInstallPerms,ManualDebug actionNode
    class PrimaryScriptUnknown,PermissionDenied,SocketError,ConfigError,OtherError errorNode
```
This troubleshooting flowchart maps out the exact debugging process we went through, but in a systematic visual format! Here's how to use it:
How to Follow the Decision Tree:
Start at the Top:

Begin with "phpBB Not Working?" and follow the yes/no paths
Each blue diamond is a check/question
Each orange rectangle is an action to take
Each red diamond is a specific error condition

Key Decision Points:

Services Running - Always check this first
Nginx Config Valid - Use sudo nginx -t
Site Enabled - Ensure only phpBB site is active
Document Root - Must point to /var/www/html/forum
PHP Socket - Check /run/php/php8.4-fpm.sock
FastCGI Config - The SCRIPT_FILENAME parameter that caused us trouble

Common Error Paths:

"Primary script unknown" → Fix SCRIPT_FILENAME parameter
"Permission denied" → Fix file ownership/permissions
Socket errors → Restart PHP-FPM
Config errors → Fix nginx syntax

Integration with Scripts:
You can use this flowchart alongside the troubleshooting script:
bash# Run specific checks based on where you are in the tree
sudo bash phpbb_troubleshoot.sh --services    # Services check
sudo bash phpbb_troubleshoot.sh --nginx       # Nginx config check
sudo bash phpbb_troubleshoot.sh --permissions # Permission check
sudo bash phpbb_troubleshoot.sh --web         # Web access test
This visual guide would have saved us a lot of time during our debugging session - it shows exactly which path to take based on each test result, and includes all the specific commands needed to fix each issue we encountered!
