import Image from "next/image";

import { CHAR } from "../constants";

const CHARACTERS = [
  { src: CHAR.prince, name: "왕자 도담이", frame: "f-prince", alt: "왕관을 쓴 왕자 도담이 캐릭터" },
  { src: CHAR.princess, name: "공주 도담이", frame: "f-princess", alt: "공주 도담이 캐릭터" },
  { src: CHAR.trumpeter, name: "나팔수 도담이", frame: "f-trumpeter", alt: "나팔을 든 나팔수 도담이 캐릭터" },
];

export function LandingCharacters() {
  return (
    <section className="landing-section" aria-labelledby="landing-characters-title">
      <div className="landing-container">
        <div className="landing-section-head">
          <h2 id="landing-characters-title" className="crayon-underline">
            함께할 도담이를 골라요
          </h2>
          <p>아이가 고른 도담이가 활동 화면에 나와요.</p>
        </div>

        <div className="landing-characters-grid">
          {CHARACTERS.map((character) => (
            <article className="landing-character-card" key={character.name}>
              <div className={`landing-character-frame ${character.frame}`}>
                <Image
                  className="landing-character-img"
                  src={character.src}
                  alt={character.alt}
                  width={300}
                  height={300}
                />
              </div>
              <span className="landing-character-name">{character.name}</span>
            </article>
          ))}
        </div>

        <p className="landing-characters-note">
          캐릭터는 앞으로 더 추가될 예정이에요.
        </p>
      </div>
    </section>
  );
}
