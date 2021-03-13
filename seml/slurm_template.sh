#!/bin/bash
{sbatch_options}

# Move either to project root dir or the config file path.
cd {working_dir}

# Print job information
echo "Starting job ${{SLURM_JOBID}}"
echo "SLURM assigned me the node(s): $(squeue -j ${{SLURM_JOBID}} -O nodelist:1000 | tail -n +2 | sed -e 's/[[:space:]]*$//')"

# Activate Anaconda environment
if {use_conda_env}; then
    CONDA_BASE=$(conda info --base)
    source $CONDA_BASE/etc/profile.d/conda.sh
    conda activate {conda_env}
fi

# Chunked list with all experiment IDs
all_exp_ids=({exp_ids})

# Get experiment IDs for this Slurm task
exp_ids_str="${{all_exp_ids[$SLURM_ARRAY_TASK_ID]}}"
IFS=";" read -r -a exp_ids <<< "$exp_ids_str"

# Create directory for the source files in MongoDB
if {with_sources}; then
    rdm=$RANDOM # Random number for temp dir
    tmpdir="/tmp/$rdm"
    declare -i ctr=0
    while [ -d $tmpdir -a $ctr -le 100 ]; do
        tmpdir="/tmp/$RANDOM"
        ctr=$ctr+1
    done
    if [ $ctr -ge 100 ]; then
        echo "Could not create a temp dir"
        exit 99
    fi
    mkdir $tmpdir
    # Prepend the temp dir to $PYTHONPATH so it will be used by python.
    export PYTHONPATH="$tmpdir:$PYTHONPATH"
fi

# Start experiments in separate processes
process_ids=()
for exp_id in "${{exp_ids[@]}}"; do
    cmd=$(python -c '{prepare_experiment_script}' --experiment_id ${{exp_id}} --db_collection_name {db_collection_name} {sources_argument} --verbose {verbose} --unobserved {unobserved} --post-mortem {post_mortem} --debug-server {debug_server})

    ret=$?
    if [ $ret -eq 0 ]; then
        if {parallel_processing}; then
            eval $cmd &
        else
            eval $cmd
        fi
        process_ids+=($!)
    elif [ $ret -eq 1 ]; then
        echo "WARNING: Experiment with ID ${{exp_id}} does not have status PENDING and will not be run."
    elif [ $ret -eq 2 ]; then
        (>&2 echo "ERROR: Experiment with id ${{exp_id}} not found in the database.")
    fi
done

# Print process information
echo "Experiments are running under the following process IDs:"
num_it=${{#process_ids[@]}}
for ((i=0; i<$num_it; i++)); do
    echo "Experiment ID: ${{exp_ids[$i]}}	Process ID: ${{process_ids[$i]}}"
done
echo

# Wait for all experiments to finish
wait

# Delete temporary source files
if {with_sources}; then
    rm -rf $tmpdir
fi
