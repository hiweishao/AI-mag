function master_compute(file_compute, file_export, sweep, n_split, data_ann, data_compute)

% name
fprintf('################## master_compute\n')

% load
fprintf('load\n')
data_fem_ann = load(file_export);

% ann_fem
fprintf('ann fem\n')
ann_fem_obj = AnnFem(data_fem_ann, data_ann.geom_type, data_ann.eval_type);

fprintf('sweep\n')
[n_sol, var] = get_sweep(sweep);

fprintf('split\n')
[n_chunk, idx_chunk] = get_chunk(n_split, n_sol);

fprintf('run\n')
for i=1:n_chunk
    fprintf('    %d / %d\n', i, n_chunk)
    
    % slice
    var_tmp =  get_struct_filter(var, idx_chunk{i});
    n_sol_tmp = length(idx_chunk{i});
    
    % get data
    data_const = data_compute.data_const;
    data_vec = data_compute.fct_data_vec(var_tmp);
    
    % inductor
    inductor_compute_obj = design.InductorCompute(n_sol_tmp, data_vec, data_const, ann_fem_obj);
    [is_valid, fom_tmp] = inductor_compute_obj.get_fom();
    
    % operating
    excitation = data_compute.fct_excitation(var_tmp, fom_tmp);
    field = fieldnames(excitation);
    for j=1:length(field)
        excitation_pts = excitation.(field{j});
        [is_valid_pts, operating_pts] = inductor_compute_obj.get_operating(excitation_pts);
        operating_tmp.(field{j}) = struct('is_valid', is_valid_pts, 'operating', operating_pts);
    end
    
    % assign
    n_valid(i) = nnz(is_valid);
    fom(i) = get_struct_filter(fom_tmp, is_valid);
    operating(i) = get_struct_filter(operating_tmp, is_valid);
end

fprintf('assemble\n')
n_valid = sum(n_valid);
fom = get_struct_assemble(fom);
operating = get_struct_assemble(operating);

% disp
fprintf('size\n')
fprintf('    n_sol = %d\n', n_sol)
fprintf('    n_valid = %d\n', n_valid)

% save
fprintf('save\n')
save(file_compute, 'n_valid', 'n_sol', 'fom', 'operating')

fprintf('################## master_compute\n')

end
