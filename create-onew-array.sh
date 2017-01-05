#!/bin/sh

# set start pattern -> first one to export
start_pattern="dummy" # exports all captured frames
start_pattern=09883081

# set stop pattern -> last one to export
stop_pattern="dummy" # exports all captured frames
#stop_pattern=1000ce50b41341000_00a489a81341000_040f1b00000000 # may differ a bit
stop_pattern=1000ce50b41341000000a489a813410000040f1b00000000

# get input filename
in_file=$1

# set output filename
out_file=$in_file.c

# set temporary filename
temp_file=$in_file.temp

# delete eventually existing output file
rm $out_file

# init variables
export_frames=0 # 1 when start pattern was recognized
stop_export=0 # 1 when stop pattern was recognized

# export relevant data
tshark -r $in_file  -Y "!(usb.function == 0x000b) && !(usb.control_stage == 2)" -E separator=, -T fields -e usb.transfer_type -e usb.endpoint_number -e usb.setup.bRequest -e usb.setup.wValue -e usb.setup.wIndex -e usb.data_len -e usb.control.Response -e usb.capdata > $temp_file

# remove colons inside the hex-strings
sed -i 's/://g' $temp_file

# write C structure header to output file
echo "struct xonew_cfg xonew_cfg[] = {" >> $out_file
echo "/* transfer_type" >> $out_file
echo "   |     endpoint_number" >> $out_file
echo "   |     |   request" >> $out_file
echo "   |     |     |   value   index   length   data/ response" >> $out_file
echo "   |     |     |     |       |       |      |" >> $out_file
echo "   V     V     V     V       V       V      V */" >> $out_file

# process line by line
while read line_in && [ $stop_export -eq 0 ]
do
    # extract the single elements
    transfer_type=${line_in%%,*}
    remaining=${line_in#*,}
    endpoint_number=${remaining%%,*}
    remaining=${remaining#*,}
    request=${remaining%%,*}
    remaining=${remaining#*,}
    value=${remaining%%,*}
    remaining=${remaining#*,}
    index=${remaining%%,*}
    remaining=${remaining#*,}
    length=${remaining%%,*}
    remaining=${remaining#*,}
    response=${remaining%%,*}
    remaining=${remaining#*,}
    data=${remaining%%,*}

    # make integers from the values
    transfer_type=$(($transfer_type))
    endpoint_number=$(($endpoint_number))
    request=$(($request))
    value=$(($value))
    index=$(($index))
    length=$(($length))

    # copy bulk data to response
    if [ $transfer_type -eq 3 ]; then
        response=$data
    fi

    # detect start pattern
    if [ "$response" == "$start_pattern" ]; then
        export_frames=1
    fi

    # handle control transfers
    if [ $transfer_type -eq 2 ]; then
        # differentiate between control setup stage and data stage
        if [ -z "$response" ]; then # setup stage
            # prepare line
            ctrl_line_out=$(printf "{0x%02x, 0x%02x, 0x%02x, 0x%04x, 0x%04x" $transfer_type $endpoint_number $request $value $index)
        else # data stage
            # prepare line
            ctrl_line_out=$(printf "%s, 0x%04x, \"%s\"},\n" "$ctrl_line_out" $length $response)

            # when start pattern was recognized
            if [ $export_frames -eq 1 ]; then
                # write line to output file
                echo "$ctrl_line_out" >> $out_file
            fi
        fi
    fi

    # handle bulk transfers
#    if [ $transfer_type -eq 3 ]; then # consider bulk inputs
    if [ $transfer_type -eq 3 ] && [ $endpoint_number -eq 4 ]; then # ignore bulk inputs
        # prepare line
        bulk_line_out=$(printf "{0x%02x, 0x%02x, 0x%02x, 0x%04x, 0x%04x, 0x%04x, \"%s\"},\n" $transfer_type $endpoint_number $request $value $index $length $data)

        # when start pattern was recognized
        if [ $export_frames -eq 1 ]; then
            # write line to output file
            echo "$bulk_line_out" >> $out_file
        fi
    fi

    # detect stop pattern
    if [ "$response" == "$stop_pattern" ]; then
        stop_export=1
    fi

done < $temp_file

# write C structure footer to output file
echo "{-1}" >> $out_file
echo "};" >> $out_file

# delete temporary file
rm $temp_file
