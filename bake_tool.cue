package bake

command: {
  image: #Dubo & {
    target: "transformer"
    args: {
      BUILD_TITLE: "Rudder Transformer"
      BUILD_DESCRIPTION: "A dubo image for Rudder based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
      BASE_BASE: string | * "docker.io/dubodubonduponey/base"
      BUILDER_BASE: "\(BASE_BASE):builder-node-\(args.DEBOOTSTRAP_SUITE)-\(args.DEBOOTSTRAP_DATE)"
    }
    platforms: [
      AMD64,
    ]
  }
}
