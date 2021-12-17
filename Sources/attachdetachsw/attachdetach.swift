import Foundation
import DI2Support

let fm = FileManager.default

func resolveSymlinks(ofPath path: String) -> String {
    let resolvedPath = try? fm.destinationOfSymbolicLink(atPath: path)
    // Return the resolved path if we can get ti
    // otherwise return the original path
    return resolvedPath ?? path
}

func getIoctlNumber(group: Character, number n:UInt) -> UInt {
    let void = UInt(IOC_VOID)
    let g: UInt = UInt(group.asciiValue!) << 8
    
    return void | g | n
}

func detachDisk(diskPath path: String, completionHandler: (_ didDetach: Bool, _ errorEncountered: String?) -> Void) {
    let fd = open(path, O_RDONLY)
    guard fd != -1 else {
        // Convert C-String strerror to swift
        let errorEncountered = String(cString: strerror(errno))
        return completionHandler(false, errorEncountered)
    }
    
    let ioctlEjectCode = getIoctlNumber(group: "d", number: 21)
    
    let ret = ioctl(fd, ioctlEjectCode)
    guard ret != -1 else {
        let errorEncountered = String(cString: strerror(errno))
        return completionHandler(false, errorEncountered)
    }
    
    return completionHandler(true, nil)
}

func AttachDMG(atPath path: String, completionHandler: (DIDeviceHandle?, Error?) -> Void) {
    var AttachParamsErr: NSError?
    let AttachParams = DIAttachParams(url: URL(fileURLWithPath: path), error: AttachParamsErr)
    if let AttachParamsErr = AttachParamsErr {
        return completionHandler(nil, AttachParamsErr)
    }
    
    // Set the filemode
    // if the user didn't specify it by the command line, it'll be 0
    AttachParams?.fileMode = returnFileModeFromCMDLine()
    
    AttachParams?.autoMount = CMDLineArgs.contains("-s") || CMDLineArgs.contains("--set-auto-mount")
    
    // The handler which will contain information about the specified disk
    var Handler: DIDeviceHandle?
    
    var AttachErr: NSError?
    DiskImages2.attach(with: AttachParams, handle: &Handler, error: &AttachErr)
    
    return completionHandler(Handler, AttachErr)
}

/// Returns the Attach filemode specified by the user using the `--file-mode=/-f=` options
func returnFileModeFromCMDLine() -> Int64 {
    /// The array who's first element (may) be the specified filemode
    let fileModeArray = CMDLineArgs.filter {
        // First lets filter the array by the element that contains --file-mode= or -f= in it
        $0.hasPrefix("--file-mode=") || $0.hasPrefix("-f=")
    }.map {
        // And now lets remove --file-mode=/-f= from the string
        $0.replacingOccurrences(of: "--file-mode=", with: "")
            .replacingOccurrences(of: "-f=", with: "")
    }.compactMap {
        // And now lets allow only Int64 in the array
        Int64($0)
    }
    
    if fileModeArray.isEmpty {
        return 0
    }
    return fileModeArray[0]
}

/// Returns the original image URL
/// that a disk was attached with
func getImageURLOfDisk(atPath path: String, completionHandler: (URL?, Error?) -> Void) {
    
    var ImageURLError: NSError?
    let url = URL(fileURLWithPath: path)
    do {
        let ImageURL = try DiskImages2.imageURL(
            fromDevice: url
        )
        return completionHandler(ImageURL as? URL, nil)
    } catch {
        return completionHandler(nil, error)
    }
}

let helpMessage = """
AttachDetachSW --- By Serena-io
A CommandLine Tool to attach and detach DMGs on iOS
Usage: attachdetachsw [--attach/-a | --detach/-d] [FILE], where FILE is a Disk Name to detach or a DMG to attach
Options:

    General Options:
        -a, --attach    [DMGFILE]                  Attach the specified DMG File
        -d, --detach    [DISKNAME]                 Detach the specified Disk name
        -i, --image-url [DISKNAME]                 Print the original image url that the specified disk name was attached with

    Attach Options:
        -f, --file-mode=FILE-MODE                  Specify a FileMode to attach the DMG with, specified FileMode must be a number
        -s, --set-auto-mount                       Sets Auto-Mount to true while attaching
        -r, --reg-entry-id                         Prints the RegEntryID of the disk that the DMG was attached to
        -o, --all-dirs                             Prints all the directories to which the DMG was attached to

Example usage:
    attachdetachsw --attach randomDMG.dmg
    attachdetachsw --detach disk8
"""
