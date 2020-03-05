# Windows_errors_report
 
Should be usefull to know if domain servers have common errors during last month:
 
• Forms a list of those servers whose objects are turned on, accessed DC no more than 14 days ago, whose OU contains servers and not contains test;

• For each of received servers via WinRM script gets a list of errors;

• If no values are received during 5 minutes - report to log file and continue with another server;

• If errors were received during data collection - output to the log file;

• Get eventlog errors values, count the number of duplicates, write information to a csv file;

• Sends an email without authorization with results.
