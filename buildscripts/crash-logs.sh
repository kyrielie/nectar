#!/bin/sh

# PRODUCT_NAME is "Nectar" (xcconfig/NetNewsWire_iOSapp_target.xcconfig),
# not "NetNewsWire" -- fixed to match, or this glob silently matches
# nothing and the script prints nothing without any error.
for filename in ~/Library/Logs/DiagnosticReports/Nectar*.crash; do
    cat $filename
done