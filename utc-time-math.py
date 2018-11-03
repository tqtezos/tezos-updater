### Quick UTC time math script that calculates the difference in seconds between two timestamps
### Written by Luke Youngblood, luke@blockscale.net

import datetime
import sys

date_format = "%Y-%m-%dT%H:%M:%SZ"

response_timestamp = datetime.datetime.strptime(sys.argv[1], date_format)
current_timestamp = datetime.datetime.strptime(sys.argv[2], date_format)

if response_timestamp and current_timestamp and (current_timestamp - response_timestamp).total_seconds() <= float(sys.argv[3]):
	print("Timestamp "+str(response_timestamp)+" is within "+sys.argv[3]+" seconds of "+str(current_timestamp)+" - delta is "+str((current_timestamp - response_timestamp).total_seconds()))
	exit(0)
else:
	print("Timestamp "+str(response_timestamp)+" is NOT within "+sys.argv[3]+" seconds of "+str(current_timestamp)+" - delta is "+str((current_timestamp - response_timestamp).total_seconds()))
	exit(1)