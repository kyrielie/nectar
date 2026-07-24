// Empty marker file.
//
// SwiftPM/Xcode can misclassify a target that contains only resources
// (no .swift/.c/.m sources) and fail package resolution with:
//   public headers ("include") directory path for 'RSCoreResources'
//   is invalid or not contained in the target
//
// Having at least one Swift source file in the target avoids that.
