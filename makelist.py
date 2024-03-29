import os

def recursive_file_paths(folder_path):
    file_paths = []
    for dirpath, _, filenames in os.walk(folder_path):
        for filename in filenames:
            file_paths.append(os.path.join(dirpath, filename))
    return file_paths

def write_paths_to_file(file_paths, output_file):
    with open(output_file, 'w') as f:
        lpaths = [os.path.relpath(path).replace("\\", "/") for path in file_paths]
        formatted_paths = [f'/{lpath}' for lpath in lpaths]
        formatted_paths.append("/init.lua")
        f.write('\n'.join(formatted_paths))

if __name__ == "__main__":
    current_directory = os.path.dirname(os.path.abspath(__file__))
    sys_directory = os.path.join(current_directory, 'system')
    out_file_path = os.path.join(current_directory, 'installer/filelist.txt')

    file_paths = recursive_file_paths(sys_directory)
    write_paths_to_file(file_paths, out_file_path)
