
#clean up the priority app format to upload to POWERBI
with open('priorityapp.txt', 'r') as f, open('output.txt', 'w') as fo:
    for line in f:
        fo.write(line.replace('"', '').replace("'", ""))

